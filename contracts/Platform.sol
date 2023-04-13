pragma solidity ^0.5.0;

import "./Account.sol";
import "./Event.sol";
import "./Ticket.sol";
import "./EventToken.sol";

contract Platform {
    Account accountContract;
    EventToken eventTokenContract;
    Event eventContract;
    Ticket ticketContract;

    event BidCommenced (uint256 eventId);
    event BidPlaced (uint256 eventId, address buyer, uint256 tokenBid);
    event BidUpdate (uint256 eventId, address buyer, uint256 tokenBid);
    event BidClosed (uint256 eventId);
    event BuyTicket (uint256 eventId, address buyer);
    event RefundTicket (uint256 ticketId, address refunder);
    event SellerEventEnd (uint256 eventId);
    event OwnerEventEnd (uint256 eventId);

    mapping(address => uint256) sellerDepositedValue;
    address owner;

    // Platform can only exist if other contracts are created first
    constructor(Account accountAddr, EventToken eventTokenAddr, Event eventAddr, Ticket ticketAddr) public {
        accountContract = accountAddr;
        eventTokenContract = eventTokenAddr;
        eventContract = eventAddr;
        ticketContract = ticketAddr;
        owner = msg.sender;
    }

    /**
     * param quantity                       quantity of tickets in bid
     * param pricePerTicket                 price per ticket in bid
     * param tokenPerTicket                 token per ticket in bid
     * param firstIndexForEventBiddings     first index of bid in eventBiddings mapping for O(1) lookup 
     */
    struct bidInfo {
        uint256 quantity;
        uint256 pricePerTicket;
        uint256 tokenPerTicket;
        uint256 firstIndexForEventBiddings; // For ease of updating bid
    }

    mapping(uint256 => uint256) public eventTopBid; // eventId => topBid
    mapping(uint256 => mapping(uint256 => address[])) public eventBiddings; // eventId => (tokenBid => addressArray) 
    mapping(address => mapping(uint256 => bidInfo)) public addressBiddings; // address => (eventId => bidInfo)

    /* Ensure caller is a buyer */
    modifier isBuyer() {
        require(accountContract.viewAccountState(msg.sender) == accountContract.getUnverifiedStatus(), "You are not a buyer");
        _;
    }

    /* Ensure caller is a verified seller */
    modifier isOrganiser() {
        require(accountContract.viewAccountState(msg.sender) == accountContract.getVerifiedStatus(),"You are not a verified seller");
        _;
    }

    /**
     * list event on platform
     *
     * param title                                      title of event
     * param venue                                      venue where event will be held at
     * param year, month, day, hour, minute, second     date and time of event
     * param capacity                                   capacity of event
     * param ticketsLeft                                event tickets left 
     * param priceOfTicket                              price of ticket
     * param seller                                     organiser / seller of event ticket   
     */
    function listEvent(string memory title,
        string memory venue,
        uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second,
        uint256 capacity,
        uint256 priceOfTicket,
        address seller) public payable isOrganiser() returns (uint256) {
        // price of ticket here will be multiply by 50,000 wei when seller list so when buyer wants to buy, they have to send in the amount of wei required
        // however msg.value here will not be sent to event contract. msg.value at event contract is 0.
        require(msg.value >= calMinimumDeposit(capacity,priceOfTicket) * 1 wei, "Insufficient deposits. Need deposit minimum (capacity * priceOfTicket)/2 * 50000 wei to list event.");

        uint256 newEventId = eventContract.createEvent(title, venue, year, month, day, hour, minute, second, capacity, priceOfTicket, seller);
        sellerDepositedValue[msg.sender] = msg.value;
        return newEventId;
    }

    /**
     * commence the bidding of event
     *
     * param eventId    id of event
     */
    function commenceBidding(uint256 eventId) public {
        require(msg.sender == eventContract.getEventSeller(eventId), "Only seller can commence bidding");
        require(eventContract.getEventState(eventId) == Event.eventState.initial, "Event not in initial state");

        eventContract.setEventState(eventId, Event.eventState.bidding);
        emit BidCommenced(eventId);
    }

    /**
     * buyer place bid for event
     *
     * param eventId    id of event
     * param quantity   quantity of tickets to bid
     * param tokenBid   tokens to use for bidding per ticket
     */
    function placeBid(uint256 eventId, uint8 quantity, uint256 tokenBid) public payable isBuyer() {
        require(eventContract.getEventState(eventId) == Event.eventState.bidding, "Event not open for bidding");
        require(quantity > 0, "Quantity of tickets must be at least 1");
        require(quantity <= 4, "You have passed the maximum bulk purchase limit");
        require(msg.value >= eventContract.getEventTicketPrice(eventId) * quantity, "Buyer has insufficient ETH");
        require(eventTokenContract.checkEventTokenOf(msg.sender) >= tokenBid * quantity, "Buyer has insufficient EventTokens");
        
        // Burn tokenBid & Transfer ETH to contract
        if (tokenBid > 0) {
            eventTokenContract.burnToken(tokenBid * quantity, msg.sender);
        }
        msg.sender.transfer(msg.value - (eventContract.getEventTicketPrice(eventId) * quantity)); // transfer remaining back to buyer
    
        // Record eventBiddings
        uint256 firstIdx;
        for (uint8 i = 0; i < quantity; i++) {
            eventBiddings[eventId][tokenBid].push(msg.sender);
            if (i == 0) {
                firstIdx = eventBiddings[eventId][tokenBid].length - 1;
            }
        }

        // Record bidInfo for ease of future refund / update 
        bidInfo memory newBidInfo = bidInfo(quantity, eventContract.getEventTicketPrice(eventId), tokenBid, firstIdx);
        addressBiddings[msg.sender][eventId] = newBidInfo;
        
        // Update top bid
        if (tokenBid > eventTopBid[eventId]) {
            eventTopBid[eventId] = tokenBid;
        }
        emit BidPlaced(eventId, msg.sender, tokenBid);
    }

    /**
     * allow buyer to update bid
     *
     * param eventId    id of event
     * param tokenBid   tokens to use for bidding per ticket
     */
    function updateBid(uint256 eventId, uint256 tokenBid) public isBuyer() {
        require(eventContract.getEventState(eventId) == Event.eventState.bidding, "Event not open for bidding");

        bidInfo memory currentBidInfo = addressBiddings[msg.sender][eventId];
        require(currentBidInfo.quantity != 0, "Cant update bid without placing bid first");
        require(tokenBid > currentBidInfo.tokenPerTicket, "New token bid must be higher than current bid");

        // Calculate additional tokens needed and burn event tokens
        uint256 tokenDifference = tokenBid - currentBidInfo.tokenPerTicket;
        uint256 totalTokenDifference = tokenDifference * currentBidInfo.quantity;
        require(eventTokenContract.checkEventTokenOf(msg.sender) >= totalTokenDifference, "Buyer has insufficient EventTokens to update bid");
        eventTokenContract.burnToken(totalTokenDifference, msg.sender);

        // Delete old bid
        for (uint256 i = currentBidInfo.firstIndexForEventBiddings; i < currentBidInfo.firstIndexForEventBiddings + currentBidInfo.quantity; i++) {
            delete eventBiddings[eventId][currentBidInfo.tokenPerTicket][i];
        }

        // Add new bid into eventBiddings
        uint256 firstIdx;
        for (uint8 i = 0; i < currentBidInfo.quantity; i++) {
            eventBiddings[eventId][tokenBid].push(msg.sender);
            if (i == 0) {
                firstIdx = eventBiddings[eventId][tokenBid].length - 1;
            }
        }

        // Update bidInfo
        currentBidInfo.tokenPerTicket = tokenBid;
        currentBidInfo.firstIndexForEventBiddings = firstIdx;
        addressBiddings[msg.sender][eventId] = currentBidInfo;

        // Update top bid
        if (tokenBid > eventTopBid[eventId]) {
            eventTopBid[eventId] = tokenBid;
        }

        emit BidUpdate(eventId, msg.sender, tokenBid);
    }

    /**
     * close bidding for specific event and transfer tickets to top bidders while returning ETH to unsuccessful bidders
     *
     * param eventId    id of event
     */
    function closeBidding(uint256 eventId) public {
        require(msg.sender == eventContract.getEventSeller(eventId), "Only seller can close bidding");
        require(eventContract.getEventState(eventId) == Event.eventState.bidding, "Event not open for bidding");

        uint256 bidAmount = eventTopBid[eventId];
        uint256 ticketsLeft = eventContract.getEventTicketsLeft(eventId);
        uint256 ticketId = eventContract.getEventFirstTicketId(eventId);

        // Tickets given out starting from top bidders
        while (true) {
            address[] memory bidderList = eventBiddings[eventId][bidAmount];
            for (uint256 i = 0; i < bidderList.length; i++) {
                if (bidderList[i] == address(0)) continue; 

                if (ticketsLeft != 0) {
                    ticketContract.transferTicket(ticketId, bidderList[i]); 
                    ticketId++;
                    ticketsLeft--;
                } else { 
                    // return ETH back to unsuccessful bidders when ticketsLeft == 0 
                    address payable recipient = address(uint168(bidderList[i]));
                    recipient.transfer(eventContract.getEventTicketPrice(eventId));
                }
            }
            if (bidAmount == 0) break;
            bidAmount--;
        }
        
        // Update event tickets left
        eventContract.setEventTicketsLeft(eventId, ticketsLeft);

        // Change state to allow normal buying and refund
        eventContract.setEventState(eventId, Event.eventState.buyAndRefund);
        emit BidClosed(eventId);
    }

    /**
     * allow ticket owners to refund ticket to platform at half price 
     *
     * param ticketId    id of ticket to refund
     */
    function refundTicket(uint256 ticketId) public payable isBuyer() {
        uint256 eventId = ticketContract.getTicketEvent(ticketId);
        require(eventContract.getEventState(eventId) == Event.eventState.buyAndRefund, "Event not open for refunding");

        //Ensure ticket has been transfered to platform
        require(ticketContract.getTicketPrevOwner(ticketId) == msg.sender, "Not owner of ticket");
        require(ticketContract.getTicketOwner(ticketId) == address(this), "Ticket not transfered to platform yet");

        // Update tickets left
        eventContract.setEventTicketsLeft(eventId, eventContract.getEventTicketsLeft(eventId) + 1);
        
        // ETH transfer back to buyer at 1/2 price
        uint256 refundPrice = eventContract.getEventTicketPrice(eventId) / 2;
        msg.sender.transfer(refundPrice);

        emit RefundTicket(ticketId, msg.sender);
    }

    /**
     * allow buyers to buy available (unsold/refunded) tickets after bidding session has closed
     *
     * param eventId    id of event
     * param quantity   quantity of tickets
     */
    function buyTickets(uint256 eventId, uint8 quantity) public payable isBuyer() {
        require(eventContract.getEventState(eventId) == Event.eventState.buyAndRefund, "Event not open for buying");
        require(quantity > 0, "Quantity of tickets must be at least 1");
        require(quantity <= 4, "You have passed the maximum bulk purchase limit");
        require(eventContract.isEventIdValid(eventId) == true, "Invalid Event");
        require(eventContract.getEventTicketsLeft(eventId) >= quantity, "Not enough tickets");

        uint256 totalPrice = eventContract.getEventTicketPrice(eventId) * quantity;
        require(msg.value >= totalPrice, "Buyer has insufficient ETH to buy tickets");

        // Set remaining tickets after someone buys ticket(s)
        uint256 remainingTickets = eventContract.getEventTicketsLeft(eventId) - quantity;
        eventContract.setEventTicketsLeft(eventId,remainingTickets);

        // Transfer ticket
        uint256 firstTicketId = eventContract.getEventFirstTicketId(eventId);
        uint256 lastTicketId = firstTicketId + eventContract.getEventCapacity(eventId) - 1;

        for (lastTicketId; lastTicketId >= firstTicketId; lastTicketId--) {
            if (ticketContract.getTicketOwner(lastTicketId) == address(this)) {
                ticketContract.transferTicket(lastTicketId, msg.sender);
                quantity--;
                if (quantity == 0) break;
            }
        }

        // Update tickets left
        eventContract.setEventTicketsLeft(eventId, eventContract.getEventTicketsLeft(eventId) - quantity);

        msg.sender.transfer(msg.value - totalPrice); // transfer remaining back to buyer
        emit BuyTicket(eventId, msg.sender);
    }

    /**
     * seller requesting to end a successful event 
     *
     * param eventId    id of event
     */
    function sellerEndEvent(uint256 eventId) public isOrganiser() {
        address seller = eventContract.getEventSeller(eventId);
        require(seller == msg.sender, "Only original seller can end event");
        require(eventContract.getEventState(eventId) == Event.eventState.buyAndRefund, "Event not at buyAndRefund state");

        eventContract.setEventState(eventId, Event.eventState.sellerEventEnd);
        emit SellerEventEnd(eventId);
    }

    /**
     * owner to declare the end of a successful event, platform to transfer ETH (ticket sales and deposits) to seller
     *
     * param eventId    id of event
     */
    function endSuccessfulEvent(uint256 eventId) public {
        require(owner == msg.sender, "Only owner can call this function");
        require(eventContract.getEventState(eventId) == Event.eventState.sellerEventEnd, "Original seller has yet to end the event");

        address seller = eventContract.getEventSeller(eventId);
        address payable addr = address(uint256(seller));
        addr.transfer(sellerDepositedValue[seller]);

        // Calculating ticket sales
        uint256 numOfTicketsSold = eventContract.getEventCapacity(eventId) - eventContract.getEventTicketsLeft(eventId);
        uint256 ticketSales = numOfTicketsSold * eventContract.getEventTicketPrice(eventId);

        // Platform keeps 5% commission of ticket sales, rest goes to Seller when event ends
        uint256 sellerProfits = 95 * ticketSales /100;
        addr.transfer(sellerProfits);

        // Mint tokens for those who owns ticket
        uint256 firstTicketId = eventContract.getEventFirstTicketId(eventId);
        for (uint256 i=firstTicketId; i < firstTicketId + eventContract.getEventCapacity(eventId); i++) {
            address _to = ticketContract.getTicketOwner(i);
            uint256 ticketPrice = ticketContract.getTicketPrice(i);
            uint256 amtOfWei = (ticketPrice / 100) * 5;
            eventTokenContract.mintToken(amtOfWei, _to);
        }

        eventContract.setEventState(eventId, Event.eventState.platformEventEnd);
        emit OwnerEventEnd(eventId);
    }

    /**
     * owner to declare a failed event, platform to refund buyers of ETH and keep seller's deposit
     *
     * param eventId    id of event
     */
    function endUnsuccessfulEvent (uint256 eventId) public {
        require(owner == msg.sender, "Only platform can call this function");

        uint256 firstTicketId = eventContract.getEventFirstTicketId(eventId);
        uint256 capacity = eventContract.getEventCapacity(eventId);
        uint256 ticketPrice = eventContract.getEventTicketPrice(eventId);

        for (uint256 i = firstTicketId; i <= firstTicketId + capacity - 1; i++) {
            address payable addr = address(uint256(ticketContract.getTicketOwner(i)));
            if(addr != address(this)) {
                addr.transfer(ticketPrice);
            } 
        }

        eventContract.setEventState(eventId, Event.eventState.platformEventEnd);
        emit OwnerEventEnd(eventId);
    }

    /**
     * calculate mininum amount a seller has to deposit to list event
     *
     * param capacity       capacity of event / amount of tickets
     * param priceOfTicket  ticket price
     */
    function calMinimumDeposit(uint256 capacity, uint256 priceOfTicket) public pure returns(uint256){
        // 1USD = 50,000 wei
        return (capacity * priceOfTicket)/2 * 50000;
    }

    /**
     * owner withdraw ETH from contract
     *
     * param amt amount of ETH to withdraw
     */
    function withdraw(uint256 amt) public payable {
        require(msg.sender == owner, "Only owner can withdraw");
        require(address(this).balance >= amt, "Not enough ETH in contract");

        address payable recipient = address(uint168(owner));
        recipient.transfer(amt);
    }

}
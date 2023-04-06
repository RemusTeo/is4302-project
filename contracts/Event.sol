pragma solidity ^0.5.0;

import "./DateTime.sol";
import "./Ticket.sol";

contract Event {

    Ticket ticketContract;

    constructor(Ticket ticketAddress) public {
        ticketContract = ticketAddress;
    }

    /**
     * enum containing 'bid' state
     * initial:             initial state before bidding
     * bidding:             bidding state when bid commences
     * buyAndRefund:        buy and refund state after bid closes
     * sellerEventEnd:      seller declare end of event
     * platformEventEnd:    platform declare end of event
     */
    enum eventState { initial, bidding, buyAndRefund, sellerEventEnd, platformEventEnd }

    /**
     * param title          title of event
     * param venue          venue where event will be held at
     * param dataAndTime    date and time of event
     * param capacity       capacity of event
     * param ticketsLeft    event tickets left 
     * param priceOfTicket  price of ticket
     * param seller         organiser / seller of event ticket   
     * param eventState     state of event: initial, bidding, buyAndRefund, sellerEventEnd, platformEventEnd
     * param firstTicketId  id of first ticket sold
     */
    struct eventObj {
        string title;
        string venue;
        uint256 dateAndTime;
        uint256 capacity;
        uint256 ticketsLeft;
        uint256 priceOfTicket;
        address seller;
        eventState state;
        uint256 firstTicketId;
    }

    uint256 public numEvents = 0; // Total number of events
    mapping(uint256 => eventObj) public events; // Storing of events

    // modifier to ensure eventId is valid
    modifier validEventId(uint256 eventId) {
        require(eventId < numEvents);
        _;
    }

    /**
     * creates a event and generates tickets
     *
     * param title                                      title of event
     * param venue                                      venue where event will be held at
     * param year, month, day, hour, minute, second     date and time of event
     * param capacity                                   capacity of event
     * param ticketsLeft                                event tickets left 
     * param priceOfTicket                              price of ticket
     * param seller                                     organiser / seller of event ticket   
     */
    function createEvent(
        string memory title,
        string memory venue,
        uint256 year, uint256 month, uint256 day, uint256 hour, uint256 minute, uint256 second,
        uint256 capacity,
        uint256 priceOfTicket,
        address seller
    ) public returns (uint256) {
        require(DateTime.timestampFromDateTime(year, month, day, hour, minute, second) > now, "Invalid Date and Time");

        eventObj memory newEvent = eventObj(
            title,
            venue,
            DateTime.timestampFromDateTime(year, month, day, hour, minute, second),
            capacity,
            capacity,
            priceOfTicket,
            seller,
            eventState.initial,
            0
        );

        uint256 newEventId = numEvents++;
        events[newEventId] = newEvent;

        // Generate Tickets
        uint256 firstTicketId = generateEventTickets(msg.sender, newEventId, priceOfTicket, Ticket.category.standard, capacity);

        setEventFirstTicketId(newEventId, firstTicketId);

        return newEventId;
    }

    /**
     * generate event tickets
     *
     * param owner          owner of tickets
     * param eventId        id of event
     * param price          price of ticket
     * param cat            seat category of ticket
     * param numOfTickets   event tickets available 
     */
    function generateEventTickets(address owner, uint256 eventId, uint256 price, Ticket.category cat, uint256 numOfTickets) public validEventId(eventId) returns (uint256) {
        uint256 firstTicketId;
        for (uint256 i = 0; i < numOfTickets; i++) {
            if (i == 0) {
                firstTicketId = ticketContract.add(owner, eventId, price, cat, i);
            } else {
                ticketContract.add(owner, eventId, price, cat, i);
            }
        }
        return firstTicketId;
    } 


    /**
     * check if eventId is valid
     *
     * param eventId    id of event
     */
    function isEventIdValid(uint256 eventId) public view returns(bool) {
        return eventId < numEvents;
    }

    /**
     * get title of event
     *
     * param eventId    id of event
     */
    function getEventTitle(uint256 eventId) public view validEventId(eventId) returns (string memory) {
        return events[eventId].title;
    }

    /**
     * get venue of event
     *
     * param eventId    id of event
     */
    function getEventVenue(uint256 eventId) public view validEventId(eventId) returns (string memory) {
        return events[eventId].venue;
    }

    /**
     * get date and time of event
     *
     * param eventId    id of event
     */
    function getEventDateAndTime(uint256 eventId) public view validEventId(eventId) returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        return DateTime.timestampToDateTime(events[eventId].dateAndTime);
    }

    /**
     * get capacity of event
     *
     * param eventId    id of event
     */
    function getEventCapacity(uint256 eventId) public view validEventId(eventId) returns (uint256) {
        return events[eventId].capacity;
    }

    /**
     * get tickets left for event
     *
     * param eventId    id of event
     */
    function getEventTicketsLeft(uint256 eventId) public view validEventId(eventId) returns (uint256) {
        return events[eventId].ticketsLeft;
    }

    /**
     * get ticket price for event
     *
     * param eventId    id of event
     */
    function getEventTicketPrice(uint256 eventId) public view validEventId(eventId) returns (uint256) {
        return events[eventId].priceOfTicket;
    }
    
    /**
     * get address of event seller
     *
     * param eventId    id of event
     */
    function getEventSeller(uint256 eventId) public view validEventId(eventId) returns (address) {
        return events[eventId].seller;
    }

    /**
     * get state of event
     *
     * param eventId    id of event
     */
    function getEventState(uint256 eventId) public view validEventId(eventId) returns (eventState) {
        return events[eventId].state;
    }

    /**
     * get first ticket id of event
     *
     * param eventId    id of event
     */
    function getEventFirstTicketId(uint256 eventId) public view validEventId(eventId) returns (uint256) {
        return events[eventId].firstTicketId;
    }

    /**
     * set state of event
     *
     * param eventId    id of event
     * param estate     eventstate
     */
    function setEventState(uint256 eventId, eventState estate) public validEventId(eventId) {
        events[eventId].state = estate;
    }

    /**
     * set first ticket id of event
     *
     * param eventId    id of event
     * param ticketId   id of ticket
     */
    function setEventFirstTicketId(uint256 eventId, uint256 ticketId) public validEventId(eventId) {
        events[eventId].firstTicketId = ticketId;
    }

    /**
     * set tickets left for event
     *
     * param eventId        id of event
     * param ticketsLeft    tickets left for event
     */
    function setEventTicketsLeft(uint256 eventId, uint256 ticketsLeft) public validEventId(eventId) {
        events[eventId].ticketsLeft = ticketsLeft;
    }

    // get latest event id
    function getLatestEventId() public view returns (uint256) {
        return numEvents - 1;
    }

   
}


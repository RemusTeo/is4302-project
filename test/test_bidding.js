const _deploy_contracts = require("../migrations/2_deploy_contracts");
const truffleAssert = require("truffle-assertions"); // npm truffle-assertions
const BigNumber = require("bignumber.js"); // npm install bignumber.js
var assert = require("assert");

var Event = artifacts.require("../contracts/Event.sol");
var Platform = artifacts.require("../contracts/Platform.sol");

const oneEth = new BigNumber(1000000000000000000); // 1 eth

contract("Bidding", function (accounts) {
    before(async () => {
        eventInstance = await Event.deployed();
        platformInstance = await Platform.deployed();
    });
    
    console.log("Testing Platform Bidding");

    it("Create Event", async () => {
        await eventInstance.createEvent("Title 0", "Venue 0", 2024, 3, 11, 12, 30, 0, 10, 10, 5, accounts[1], {from: accounts[1]});

        const title0 = await eventInstance.getEventTitle(0);

        await assert("Title 0", title0, "Failed to create event");
    });

    it("Commence Bidding", async () => {
        let bidCommenced = await platformInstance.commenceBidding(0, {from: accounts[1]});
        truffleAssert.eventEmitted(bidCommenced, "BidCommenced");
    })

    it("Place Bidding", async () => {
        let bidPlaced = await platformInstance.placeBid(0, 1, 0, {from: accounts[2], value: oneEth.multipliedBy(5)});
        truffleAssert.eventEmitted(bidPlaced, "BidPlaced");
    })

    it("Close Bidding", async () => {
        let bidClosed = await platformInstance.closeBidding(0, {from: accounts[1]});
        truffleAssert.eventEmitted(bidClosed, "BidClosed");
    })










})
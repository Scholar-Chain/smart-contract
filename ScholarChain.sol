// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*  -------- OpenZeppelin imports (npm @openzeppelin/contracts) -------- */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ScholarChain
 * @author  Scholar Chain dev
 * @notice  Escrow-NFT contract untuk penerbitan ilmiah.
 *
 * FLOW (ringkas)
 * 1.  Author mem‐submit naskah + biaya → createSubmission()
 * 2.  Publisher men-set status: review/accept/reject → publisherDecision()
 * 3.  Jika accept, publisher unggah DOI & CID IPFS → finalizeAndMint()
 * 4.  Kontrak mengirim dana ke publisher (–fee), mencetak NFT ke author.
 * 5.  Jika reject/cancel/timeout: refund sesuai tabel white-paper.
 */
contract ScholarChain is ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;         // NFT ID
    IERC20 public immutable idrx;               // stable-coin pembayaran IDRX

    uint256 public constant SERVICE_FEE_PUBLISH = 20_000 * 1e2; // Rp20k dlm wei IDRX
    uint256 public constant SERVICE_FEE_CANCEL  = 10_000 * 1e2; // Rp10k
    uint256 public reviewerSharePct = 30;       // 30 % saat batal stlh review

    uint256 public constant PUBLISHER_DEADLINE  = 30 days;
    uint256 public constant GRACE_PERIOD        = 7 days;

    enum Status { Submitted, UnderReview, Accepted, Rejected, Published, Cancelled }
    struct Article {
        address author;
        address publisher;
        uint256 amount;          // biaya publikasi
        uint256 submittedAt;
        uint256 lastActionAt;
        Status  status;
        bool    reviewed;
    }
    mapping(bytes32 => Article) public articles;   // key = articleId (hash judul+timestamp)

    /* --------------------  EVENTS  -------------------- */
    event Submitted(bytes32 indexed id, address author, address publisher, uint256 amount);
    event Decision(bytes32 indexed id, Status newStatus, bool reviewed);
    event Cancelled(bytes32 indexed id, uint256 refundAuthor, uint256 reviewerFee);
    event Published(bytes32 indexed id, uint256 tokenId, string tokenURI);

    constructor(address _idrx, address initialOwner) ERC721("ScholarChain Article", "SCHLR") Ownable(initialOwner) {
        idrx = IERC20(_idrx);
        // transferOwnership(initialOwner); // Mengatur pemilik awal kontrak
    }

    /* ============================  BUSINESS  LOGIC  ============================ */

    /// @notice Author submit naskah + biaya
    function createSubmission(
        bytes32 articleId,
        address publisher,
        uint256 amount
    ) external {
        require(articles[articleId].author == address(0), "id used");
        require(publisher != address(0) && amount >= SERVICE_FEE_PUBLISH, "bad params");

        // transfer biaya ke escrow
        require(idrx.transferFrom(msg.sender, address(this), amount), "payment fail");

        articles[articleId] = Article({
            author: msg.sender,
            publisher: publisher,
            amount: amount,
            submittedAt: block.timestamp,
            lastActionAt: block.timestamp,
            status: Status.Submitted,
            reviewed: false
        });

        emit Submitted(articleId, msg.sender, publisher, amount);
    }

    /// @notice Publisher mengambil keputusan: 0=review, 1=accept, 2=reject
    function publisherDecision(bytes32 id, uint8 decision) external {
        Article storage a = articles[id];
        require(msg.sender == a.publisher, "only publisher");
        require(a.status == Status.Submitted || a.status == Status.UnderReview, "locked");

        if (decision == 0) { // review
            a.status = Status.UnderReview;
            a.reviewed = true;
        } else if (decision == 1) { // accept
            a.status = Status.Accepted;
        } else if (decision == 2) { // reject
            _refund(a, true); // full refund – service fee dipotong
            a.status = Status.Rejected;
        } else {
            revert("bad decision");
        }
        a.lastActionAt = block.timestamp;
        emit Decision(id, a.status, a.reviewed);
    }

    /// @notice Author bisa membatalkan selama belum review
    function authorCancel(bytes32 id) external {
        Article storage a = articles[id];
        require(msg.sender == a.author, "only author");
        require(a.status == Status.Submitted, "cannot cancel");
        _refund(a, false); // full refund
        a.status = Status.Cancelled;
        emit Cancelled(id, a.amount, 0);
    }

    /// @notice Siapa pun bisa memanggil untuk membatalkan ketika publisher tidak aktif (timeout)
    function timeout(bytes32 id) external {
        Article storage a = articles[id];
        require(
            a.status == Status.Submitted || a.status == Status.UnderReview || a.status == Status.Accepted,
            "wrong state"
        );
        require(block.timestamp > a.lastActionAt + PUBLISHER_DEADLINE + GRACE_PERIOD, "still time");
        _refund(a, false); // full refund –5 % service fee
        a.status = Status.Cancelled;
        emit Cancelled(id, a.amount, 0);
    }

    /// @notice Setelah accept, publisher memanggil ini utk release dana & mint NFT
    function finalizeAndMint(
        bytes32 id,
        string memory tokenURI      // ipfs://CID/json
    ) external {
        Article storage a = articles[id];
        require(msg.sender == a.publisher, "only publisher");
        require(a.status == Status.Accepted, "not accepted");

        // kalkulasi dana
        uint256 serviceFee = SERVICE_FEE_PUBLISH;
        uint256 payout = a.amount - serviceFee;

        // kirim dana ke publisher
        require(idrx.transfer(a.publisher, payout), "payout fail");
        require(idrx.transfer(owner(), serviceFee), "fee fail");

        // mint NFT ke author
        _tokenIds.increment();
        uint256 newId = _tokenIds.current();
        _safeMint(a.author, newId);
        _setTokenURI(newId, tokenURI);

        a.status = Status.Published;
        emit Published(id, newId, tokenURI);
    }

    /* ============================  INTERNAL  ============================ */

    function _refund(Article storage a, bool afterReview) internal {
        uint256 refund;
        uint256 reviewerFee;
        uint256 serviceFee = SERVICE_FEE_CANCEL;

        if (afterReview && a.reviewed) {
            reviewerFee = (a.amount * reviewerSharePct) / 100;
            refund = a.amount - reviewerFee - serviceFee;
            require(idrx.transfer(a.publisher, reviewerFee), "reviewer fee fail");
        } else {
            refund = a.amount - serviceFee;
        }

        require(idrx.transfer(a.author, refund), "refund fail");
        require(idrx.transfer(owner(), serviceFee), "fee fail");
    }

    /* ============================  ADMIN  ============================ */
    function setReviewerShare(uint256 pct) external onlyOwner {   // 0-100
        reviewerSharePct = pct;
    }
}

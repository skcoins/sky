pragma solidity ^0.4.23;


contract Skcoin {
    using SafeMath for uint;

    /*=====================================
    =            CONSTANTS                =
    =====================================*/

    uint8 constant public                decimals = 18;//精度

    uint constant internal               TOKEN_PRICE_INITIAL = 0.000653 ether;//SKC初始价
    uint constant internal               magnitude = 2 ** 64;//量级精度

    uint constant internal               icoHardCap = 250 ether;//ICO硬顶
    //uint constant internal               addressICOLimit = 1 ether;//单个地址的ICO最大购买数量
    uint constant internal               icoMinBuyIn = 0.1 finney;//单个地址的ICO最小购买数量
    uint constant internal               icoMaxGasPrice = 50000000000 wei;//ICO的Gas单价

    uint constant internal               MULTIPLIER = 9615;//增量精度
    uint constant internal               MIN_ETH_BUYIN = 0.0001 ether;//最小Ether购买数量
    uint constant internal               MIN_TOKEN_SELL_AMOUNT = 0.0001 ether;//最小Token售卖数量
    uint constant internal               MIN_TOKEN_TRANSFER = 1e10;//最小Token转账数量
    uint constant internal               referrer_percentage = 30; //推荐奖励
    uint constant internal               user_percentage = 60; //用户占比

    uint public                          stakingRequirement = 100e18; // 推荐人获取推荐费最小持币数量

    /*================================
     =          CONFIGURABLES         =
     ================================*/

    string public                        name = "Skcoin"; //名称
    string public                        symbol = "SKC";  //缩写
    uint   internal                      tokenSupply = 0; //供应量

    mapping(address => bool)      public administrators; //管理员列表

    address internal                     platformAddress; //平台的收益地址
    address public                       bankrollAddress; //游戏的资金地址


    /*================================
     =            DATA               =
     ================================*/

    mapping(address => uint)    internal frontTokenBalanceLedger; // token bought total
    mapping(address => uint)    internal referralLedger; //推荐账本
    mapping(address => uint)    internal dividendTokenBalanceLedger_; //分红账本
    mapping(address => uint)    internal ICOBuyIn; //ICO认购记录账本

    mapping(uint8 => bool)      internal validDividendRates; //预设的分红比率
    mapping(address => bool)    internal userSelectedRate; //用户选择的分红比率
    mapping(address => uint8)   internal userDividendRate; //用户最终的分红比率
    mapping(address => uint256) internal holderIndex; // Mapping of holder addresses (index)

    address[]                   internal holders; //Token持有者数组

    uint    public                       tokensMintedDuringICO; //ICO发行的Token数量
    uint    public                       ethInvestedDuringICO; //ICO认购的Ether数量
    uint    public                       currentEthInvested; //最新的Ether认购数量
    uint    internal                     divTokenSupply = 0; //参与分红的Token数量
    uint256 internal                     dividendTotalToken; //本轮分红Token数量
    bool    public                       paused = true; //合约的状态

    bool    public                       regularPhase = false; // true-正常阶段，false-ICO阶段
    uint                                 icoOpenTime;//ICO开始时间

    /*=================================
    =            MODIFIERS            =
    =================================*/

    modifier onlyHolders() {
        require(myFrontEndTokens() > 0);
        _;
    }

    modifier onlyAdministrator(){
        require(administrators[msg.sender]);
        _;
    }

    modifier onlyBankrollContract() {
        require(msg.sender == bankrollAddress);
        _;
    }

    modifier isPaused() {
        require(paused);
        _;
    }

    modifier isNotPaused() {
        require((administrators[msg.sender] && paused) || !paused);
        _;
    }

    /*==============================
    =            EVENTS            =
    ==============================*/

    /*
    * ETH购买Skc
    */
    event OnTokenPurchase(
        address indexed customerAddress, //地址
        uint incomingEthereum, //总的ETH，包含平台抽成
        uint tokensMinted, //购买Token数
        uint tokenPrice, //token价格
        uint8 divChoice, //股息率
        address referrer //推荐人
    );

    /*
    * Token兑换ETH
    */
    event OnTokenSell(
        address indexed customerAddress, //用户地址
        uint ethereumEarned, //最终兑换的ETH数
        uint tokensBurned, //兑换ETH时使用的Token数量
        uint tokenPrice, //token价格
        uint divRate //平均股息率
    );

    /*
    * 手动触发分成
    */
    event Divide(
        address indexed administrator, //管理员地址
        uint totalToken, // 待分成总的SKC数量
        uint holderNumber //当前SKC持有人数量
    );

    /*
    * 用户选择的股息率
    */
    event UserDividendRate(
        address user,
        uint divRate
    );

    /*
    * Token转帐
    */
    event Transfer(
        address indexed from, //Token转出地址
        address indexed to, //Token转入地址
        uint tokens //token数量
    );

    /*
    * 将Token授权给其它地址
    */
    event Approval(
        address indexed tokenOwner, //Token的原来持有者
        address indexed spender, //被授权人，可以花费tokenOwner授权数量的Token
        uint tokens //授权的Token数量
    );

    /**
     * 记录推荐人分红和Token holder 分红
     */
    event AssetsDetail(
        address indexed buyer, //购买者
        address referrer, //推荐人
        uint referrerToken, //推荐人分红
        uint tokenHolder, //持币者分红
        uint toPlatformToken //平台分红
    );

    /**
     * 记录推荐人分红和Token holder 分红
     */
    event DividendDetail(
        address indexed customerAddress, //
        uint referrerToken, //推荐人分红
        uint tokenHolder //持币者分红
    );

    event Pause(
        address indexed adminAddress
    );

    event Unpause(
        address indexed adminAddress
    );
    /*=======================================
    =            Test FUNCTIONS           =
    =======================================*/
    /**
     * 设置当前Token发行量
     */
    function setTestTotalSupply(uint256 _tokenSupply)
    public
    onlyAdministrator
    {
        tokenSupply = _tokenSupply;
    }

    /**
     * 设置当前ETH投入量
     */
    function setTestCurrentEthInvested(uint256 _currentEthInvested)
    public
    onlyAdministrator
    {
        currentEthInvested = _currentEthInvested;
    }

    /*=======================================
    =            PUBLIC FUNCTIONS           =
    =======================================*/
    constructor (address _platformAddress)
    public
    {
        platformAddress = _platformAddress;

        administrators[msg.sender] = true;

        validDividendRates[2] = true;
        validDividendRates[5] = true;
        validDividendRates[10] = true;
        validDividendRates[20] = true;
        validDividendRates[35] = true;
        validDividendRates[50] = true;
    }

    /** 获取常量的一些方法 */

    /**
     * 当前SKC的发行量\流通量
     */
    function totalSupply()
    public
    view
    returns (uint256)
    {
        return tokenSupply;
    }

    /**
     * 当前合约持有ETH数量
     */
    function totalEtherBalance()
    public
    view
    returns (uint)
    {
        return address(this).balance;
    }

    /**
     * ICO阶段募集的ETH数量
     */
    function totalEtherICOReceived()
    public
    view
    returns (uint)
    {
        return ethInvestedDuringICO;
    }

    /**
     * 调用者的SKC余额
     */
    function myFrontEndTokens()
    public
    view
    returns (uint)
    {
        return balanceOf(msg.sender);
    }

    /**
     * 获取目标地址的SKC余额
     */
    function balanceOf(address _customerAddress)
    public
    view
    returns (uint)
    {
        return frontTokenBalanceLedger[_customerAddress];
    }

    /**
     * 获取当前的所有持币用户
     */
    function allHolders()
    public
    view
    returns (address[])
    {
        return holders;
    }

    /*
    * 设置Bankroll合约地址
    */
    function setBankrollAddress(address _bankrollAddress)
    public
    onlyAdministrator
    {
        bankrollAddress = _bankrollAddress;
    }

    /**
    * 设置平台收益地址
    */
    function setPlatformAddress(address _platformAddress)
    public
    onlyAdministrator
    {
        platformAddress = _platformAddress;
        userSelectedRate[platformAddress] = true;
        userDividendRate[platformAddress] = 50;
    }

    /*
    * ETH直接购买游戏积分
    */
    function ethBuyGamePoints(uint256 _id, address _referredBy, uint8 divChoice)
    public
    payable
    isNotPaused()
    returns (uint256)
    {
        address _customerAddress = msg.sender;
        uint256 frontendBalance = frontTokenBalanceLedger[msg.sender];
        if (userSelectedRate[_customerAddress] && divChoice == 0) {
            purchaseTokens(msg.value, _referredBy);
        } else {
            buyAndSetDivPercentage(_referredBy, divChoice);
        }
        uint256 difference = SafeMath.sub(frontTokenBalanceLedger[msg.sender], frontendBalance);

        bool isSuccess = bankrollAddress.call(bytes4(keccak256("tokenToPointBySkcContract(uint256,address,uint256)")), _id, msg.sender, difference);
        require(isSuccess);
        return difference;
    }

    /*
    * SKC兑换游戏积分
    */
    function redeemGamePoints(address _caller, uint _amountOfTokens)
    public
    onlyBankrollContract
    isNotPaused()
    returns (bool)
    {
        require(frontTokenBalanceLedger[_caller] >= _amountOfTokens);

        //require(regularPhase);

        uint _amountOfDivTokens = _amountOfTokens.mul(getUserAverageDividendRate(_caller)).div(100);

        frontTokenBalanceLedger[_caller] = frontTokenBalanceLedger[_caller].sub(_amountOfTokens);
        frontTokenBalanceLedger[bankrollAddress] = frontTokenBalanceLedger[bankrollAddress].add(_amountOfTokens);
        dividendTokenBalanceLedger_[_caller] = dividendTokenBalanceLedger_[_caller].sub(_amountOfDivTokens);
        dividendTokenBalanceLedger_[bankrollAddress] = dividendTokenBalanceLedger_[bankrollAddress].add(_amountOfDivTokens);

        emit Transfer(_caller, bankrollAddress, _amountOfTokens);
        return true;
    }

    /*
    * 将当前累积的Token分给当前的持币用户
    */
    function divide()
    public
    onlyAdministrator
    {
        require(regularPhase);

        uint _dividendTotalToken = dividendTotalToken;
        uint allToken;
        for (uint i = 0; i < holders.length; i++) {
            address holder = holders[i];

            // 平台地址不再参与分红
            if(platformAddress == holder) {
                continue;
            }

            uint receivedToken = 0;
            if(frontTokenBalanceLedger[holder] > 0) {
                receivedToken = dividendTotalToken.mul(dividendTokenBalanceLedger_[holder]).div(divTokenSupply);
                uint dividendToken = receivedToken.mul(dividendTokenBalanceLedger_[holder]).div(divTokenSupply);
                divTokenSupply = divTokenSupply.add(dividendToken);
                frontTokenBalanceLedger[holder] = frontTokenBalanceLedger[holder].add(receivedToken);
                dividendTokenBalanceLedger_[holder] = dividendTokenBalanceLedger_[holder].add(dividendToken);
                allToken += receivedToken;
                emit Transfer(address(this), holder, receivedToken);
            }

            uint toReferral = referralLedger[holder];
            if(receivedToken != 0 || toReferral > 0) {
                uint referralDividendToken = toReferral.mul(dividendTokenBalanceLedger_[holder]).div(divTokenSupply);
                referralLedger[holder] = 0;

                divTokenSupply = divTokenSupply.add(referralDividendToken);
                frontTokenBalanceLedger[holder] = frontTokenBalanceLedger[holder].add(toReferral);
                dividendTokenBalanceLedger_[holder] = dividendTokenBalanceLedger_[holder].add(referralDividendToken);
                emit Transfer(address(this), holder, toReferral);
            }

            if(receivedToken != 0 || toReferral > 0) {
                emit DividendDetail(holder, toReferral, receivedToken);
            }
        }

        require(allToken == dividendTotalToken, "divided result doesn't match with the total token");

        // 本次分红完成后，重置为0
        dividendTotalToken = 0;

        emit Divide(msg.sender, _dividendTotalToken, holders.length);
    }

    /**
     * 更新持币用户
     */
    function addOrUpdateHolder(address _holderAddr)
    internal
    {
        if (holderIndex[_holderAddr] == 0) {
            holderIndex[_holderAddr] = holders.length++;
            holders[holderIndex[_holderAddr]] = _holderAddr;
        }
    }

    /**
     * ETH购买SKC，并设置选择的股息率
     */
    function buyAndSetDivPercentage(address _referredBy, uint8 _divChoice)
    public
    payable
    isNotPaused()
    returns (uint)
    {
        // require(icoPhase || regularPhase);

        if (!regularPhase) {
            uint gasPrice = tx.gasprice;

            require(gasPrice <= icoMaxGasPrice && ethInvestedDuringICO <= icoHardCap);

        }

        require(validDividendRates[_divChoice]);

        // 设置用户选择的股息率
        userSelectedRate[msg.sender] = true;
        userDividendRate[msg.sender] = _divChoice;
        emit UserDividendRate(msg.sender, _divChoice);

        // 兑换Token
        purchaseTokens(msg.value, _referredBy);
    }

    /**
     * 使用上一次选择的股息率购买SKC
     */
    function buy(address _referredBy)
    public
    payable
    isNotPaused()
    returns (uint)
    {
        require(regularPhase);
        address _customerAddress = msg.sender;
        require(userSelectedRate[_customerAddress]);
        purchaseTokens(msg.value, _referredBy);
    }

    function()
    public
    payable
    {
        revert();
    }

    /**
     * 退出项目，所有SKC转为ETH
     */
    function exit()
    public
    isNotPaused()
    {
        require(regularPhase);
        address _customerAddress = msg.sender;
        uint _tokens = frontTokenBalanceLedger[_customerAddress];

        if (_tokens > 0) sell(_tokens);
    }

    /**
     * 将Token卖成ETH
     */
    function sell(uint _amountOfTokens)
    public
    onlyHolders()
    isNotPaused()
    {
        // require(!icoPhase);
        require(regularPhase);

        require(_amountOfTokens <= frontTokenBalanceLedger[msg.sender]);

        uint _frontEndTokensToBurn = _amountOfTokens;
        uint _sellPrice = sellPrice();
        uint userDivRate = getUserAverageDividendRate(msg.sender);

        //分红率范围检查 2% ~ 50%
        require((2 * magnitude) <= userDivRate && (50 * magnitude) >= userDivRate);

        // 计算售卖时产生的分成数
        uint _dividendsToken = _frontEndTokensToBurn.mul(userDivRate).div(100);
        _frontEndTokensToBurn -= _dividendsToken;

        uint _divTokensToBurn = (_frontEndTokensToBurn.mul(userDivRate)).div(magnitude);

        uint _ether = tokensToEther_(_frontEndTokensToBurn);

        if (_ether > currentEthInvested) {
            currentEthInvested = 0;
        } else {currentEthInvested = currentEthInvested - _ether;}

        // 销毁Token
        tokenSupply = tokenSupply.sub(_frontEndTokensToBurn);
        divTokenSupply = divTokenSupply.sub(_divTokensToBurn);

        // 扣去用户的Token余额
        frontTokenBalanceLedger[msg.sender] = frontTokenBalanceLedger[msg.sender].sub(_frontEndTokensToBurn);
        dividendTokenBalanceLedger_[msg.sender] = dividendTokenBalanceLedger_[msg.sender].sub(_divTokensToBurn);

        dividendTotalToken += _dividendsToken;
        msg.sender.transfer(_ether);

        emit OnTokenSell(msg.sender, _ether, _amountOfTokens, _sellPrice, userDivRate);
        emit Transfer(msg.sender, address(this), _amountOfTokens);
    }

    /**
     * bankroll合约的转账功能
     */
    function transfer(address _toAddress, uint _amountOfTokens)
    public
    onlyBankrollContract()
    returns (bool)
    {
        require(_amountOfTokens >= MIN_TOKEN_TRANSFER
        && _amountOfTokens <= frontTokenBalanceLedger[msg.sender]);

        require(_toAddress != address(0x0));
        address _customerAddress = msg.sender;
        uint _amountOfFrontEndTokens = _amountOfTokens;

        // 计算待转出的分成Token数量
        uint _amountOfDivTokens = _amountOfFrontEndTokens.mul(getUserAverageDividendRate(_customerAddress)).div(100);

        // 转Token
        frontTokenBalanceLedger[_customerAddress] = frontTokenBalanceLedger[_customerAddress].sub(_amountOfFrontEndTokens);
        frontTokenBalanceLedger[_toAddress] = frontTokenBalanceLedger[_toAddress].add(_amountOfFrontEndTokens);
        dividendTokenBalanceLedger_[_customerAddress] = dividendTokenBalanceLedger_[_customerAddress].sub(_amountOfDivTokens);
        dividendTokenBalanceLedger_[_toAddress] = dividendTokenBalanceLedger_[_toAddress].add(_amountOfDivTokens);

        emit Transfer(_customerAddress, _toAddress, _amountOfFrontEndTokens);

        return true;
    }

    /**
     * 手动结束ICO阶段，进入正常阶段
     */
    function publicStartRegularPhase()
    public
    {
        require(now > (icoOpenTime + 2 weeks) && icoOpenTime != 0);

        // icoPhase = false;
        regularPhase = true;
    }

    /*----------  ADMINISTRATOR ONLY FUNCTIONS  ----------*/


    /**
     * 开启ICO阶段
     */
    function startICOPhase()
    onlyAdministrator()
    public
    {
        require(icoOpenTime == 0);
        // icoPhase = true;
        regularPhase = false;
        icoOpenTime = now;
    }

    /**
     * 结束ICO阶段
     */
    function endICOPhase()
    onlyAdministrator()
    public
    {
        //icoPhase = false;
        regularPhase = true;
    }

    function startRegularPhase()
    onlyAdministrator
    public
    {
        // icoPhase = false;
        regularPhase = true;
    }

    function pause()
    public
    onlyAdministrator
    isNotPaused
    {
        paused = true;
        emit Pause(msg.sender);
    }

    function unpause()
    public
    onlyAdministrator
    isPaused
    {
        paused = false;
        emit Unpause(msg.sender);
    }

    /**
     * 更新管理员状态
     */
    function setAdministrator(address _newAdmin, bool _status)
    onlyAdministrator()
    public
    {
        administrators[_newAdmin] = _status;
    }

    /**
    * 设置能够获取推荐费的最小持币数量
    */
    function setStakingRequirement(uint _amountOfTokens)
    onlyAdministrator()
    public
    {
        require(_amountOfTokens >= 100e18);
        stakingRequirement = _amountOfTokens;
    }

    function setName(string _name)
    onlyAdministrator()
    public
    {
        name = _name;
    }

    function setSymbol(string _symbol)
    onlyAdministrator()
    public
    {
        symbol = _symbol;
    }

    /*----------  HELPERS AND CALCULATORS  ----------*/

    /**
     * 获取用户当前默认的股息率
     */
    function getMyDividendRate()
    public
    view
    returns (uint8)
    {
        address _customerAddress = msg.sender;
        require(userSelectedRate[_customerAddress]);
        return userDividendRate[_customerAddress];
    }

    /**
     * 当前分成Token的总数量，类似于发行的总的股份数
     */
    function getDividendTokenSupply()
    public
    view
    returns (uint)
    {
        return divTokenSupply;
    }

    /**
     * 获取用户的分成Token数
     */
    function myDividendTokens()
    public
    view
    returns (uint)
    {
        address _customerAddress = msg.sender;
        return getDividendTokenBalanceOf(_customerAddress);
    }

    function getDividendTokenBalanceOf(address _customerAddress)
    view
    public
    returns (uint)
    {
        return dividendTokenBalanceLedger_[_customerAddress];
    }

    /**
     * 获取当前的售卖价格,以卖出0.001 ether计算
     */
    function sellPrice()
    public
    view
    returns (uint)
    {
        uint price;

        if (!regularPhase || currentEthInvested < ethInvestedDuringICO) {
            price = TOKEN_PRICE_INITIAL;
        } else {
            // 计算0.001ether购买的Token数量
            uint tokensReceivedForEth = etherToTokens_(0.001 ether);
            price = (1e18 * 0.001 ether) / tokensReceivedForEth;
        }

        // 考虑用户的平均分红率的影响
        uint theSellPrice = price.sub((price.mul(getUserAverageDividendRate(msg.sender)).div(100)).div(magnitude));

        return theSellPrice;
    }

    /**
     * 获取当前的购买价格
     */
    function buyPrice(uint dividendRate)
    public
    view
    returns (uint)
    {
        uint price;

        if (!regularPhase || currentEthInvested < ethInvestedDuringICO) {
            price = TOKEN_PRICE_INITIAL;
        } else {
            // 计算0.001ether购买的Token数量
            uint tokensReceivedForEth = etherToTokens_(0.001 ether);

            price = (1e18 * 0.001 ether) / tokensReceivedForEth;
        }

        // 考虑用户的平均分红率的影响
        uint theBuyPrice = (price.mul(dividendRate).div(100)).add(price);

        return theBuyPrice;
    }

    /**
     * 计算当前用一定量的ether能够买到的SKC数量
     */
    function calculateTokensReceived(uint _etherToSpend)
    public
    view
    returns (uint)
    {
        uint _dividends = (_etherToSpend.mul(userDividendRate[msg.sender])).div(100);
        uint _taxedEther = _etherToSpend.sub(_dividends);
        uint _amountOfTokens = etherToTokens_(_taxedEther);
        return _amountOfTokens;
    }

    /**
     * 计算当前卖出一定量的SKC能够得到ether的数量
     */
    function calculateEtherReceived(uint _tokensToSell)
    public
    view
    returns (uint)
    {
        require(_tokensToSell <= tokenSupply);
        uint _ether = tokensToEther_(_tokensToSell);
        uint userAverageDividendRate = getUserAverageDividendRate(msg.sender);
        uint _dividends = (_ether.mul(userAverageDividendRate).div(100)).div(magnitude);
        uint _taxedEther = _ether.sub(_dividends);
        return _taxedEther;
    }

    /*
     * 计算用户的平均股息率
     */
    function getUserAverageDividendRate(address user) public view returns (uint) {
        return (magnitude * dividendTokenBalanceLedger_[user]).div(frontTokenBalanceLedger[user]);
    }

    function getMyAverageDividendRate() public view returns (uint) {
        return getUserAverageDividendRate(msg.sender);
    }

    /*==========================================
    =            INTERNAL FUNCTIONS            =
    ==========================================*/

    /* Purchase tokens with Ether. */
    function purchaseTokens(uint _incomingEther, address _referredBy)
    internal
    returns (uint)
    {
        require(_incomingEther >= MIN_ETH_BUYIN || msg.sender == bankrollAddress, "Tried to buy below the min eth buyin threshold.");

        if(!regularPhase) {
            purchaseICOTokens(_incomingEther, _referredBy);
        } else {
            uint8 dividendRate = userDividendRate[msg.sender];
            uint tokenPrice = buyPrice(userDividendRate[msg.sender]);
            uint toPlatform = _incomingEther.div(100).mul(2);
            uint remainingEth = remainingEth.sub(toPlatform);
            // 购买的总的Token数，包括分成Token
            uint tokensBought = etherToTokens_(remainingEth);

            purchaseRegularPhaseTokens(_incomingEther, _referredBy);

            emit OnTokenPurchase(msg.sender, _incomingEther, tokensBought, tokenPrice, dividendRate, _referredBy);
        }
    }

    function purchaseICOTokens(uint _incomingEther, address _referredBy)
    internal
    returns (uint)
    {
        require(!regularPhase);
        uint remainingEth = _incomingEther;

        uint toPlatform = remainingEth.div(100).mul(2);
        remainingEth = remainingEth.sub(toPlatform);

        uint tokensBought = etherToTokens_(remainingEth);
        tokenSupply = tokenSupply.add(tokensBought);

        currentEthInvested = currentEthInvested.add(remainingEth);

        ethInvestedDuringICO = ethInvestedDuringICO + remainingEth;
        tokensMintedDuringICO = tokensMintedDuringICO + tokensBought;

        // 不能购买超过设置的ICO上限
        require(ethInvestedDuringICO <= icoHardCap);
        // 合约账户不允许参与ICO
        require(tx.origin == msg.sender);

        // 检查地址是否到达ICO购买上限
        ICOBuyIn[msg.sender] += remainingEth;
        //require(ICOBuyIn[msg.sender] <= addressICOLimit);

        // 如果达到设置的ICO上限就停止ICO阶段
        if (ethInvestedDuringICO == icoHardCap) {
            // icoPhase = false;
            regularPhase = true;
        }

        // 更新买到的Token数量
        frontTokenBalanceLedger[msg.sender] = frontTokenBalanceLedger[msg.sender].add(tokensBought);

        addOrUpdateHolder(msg.sender);

        if (toPlatform != 0) {platformAddress.transfer(toPlatform);}

        // 检查最终结果是否和预期一致
        uint sum = toPlatform + remainingEth - _incomingEther;
        assert(sum == 0);

        emit OnTokenPurchase(msg.sender, _incomingEther, tokensBought, TOKEN_PRICE_INITIAL, 0, _referredBy);
        emit Transfer(address(this), msg.sender, tokensBought);
    }

    function purchaseRegularPhaseTokens(uint _incomingEther, address _referredBy)
    internal
    returns (uint)
    {
        require(regularPhase);

        uint toReferrer = 0;
        uint toTokenHolders = 0;
        uint toPlatformToken = 0;

        uint dividendETHAmount;
        uint dividendTokenAmount;

        uint tokensBought;
        uint userTokensBought;


        uint toPlatform = remainingEth.div(100).mul(2);
        uint remainingEth = remainingEth.sub(toPlatform);

        // 计算Ether兑换的Token总量
        tokensBought = etherToTokens_(remainingEth);

        dividendETHAmount = remainingEth.mul(userDividendRate[msg.sender]).div(100);
        remainingEth = remainingEth.sub(dividendETHAmount);

        // 玩家最终买到的Token数量
        userTokensBought = etherToTokens_(remainingEth);
        // 分红的Token总量
        dividendTokenAmount = tokensBought.sub(userTokensBought);

        tokenSupply = tokenSupply.add(tokensBought);
        currentEthInvested = currentEthInvested.add(remainingEth);
        currentEthInvested = currentEthInvested.add(dividendETHAmount);

        /**
        * 1) 有推荐人：30% -> referrers, 60% -> user, 10% -> platform
        * 2) 无推荐人：60% -> user, 40% -> platform
        **/
        if (_referredBy != 0x0000000000000000000000000000000000000000 &&
        _referredBy != msg.sender &&
        frontTokenBalanceLedger[_referredBy] >= stakingRequirement) {
            toReferrer = (dividendTokenAmount.mul(referrer_percentage)).div(100);
            referralLedger[_referredBy] = referralLedger[_referredBy].add(toReferrer);
        }
        toTokenHolders = (dividendTokenAmount.mul(user_percentage)).div(100);
        toPlatformToken = (dividendTokenAmount.sub(toReferrer)).sub(toTokenHolders);

        // 更新分红账本
        dividendTotalToken = dividendTotalToken.add(toTokenHolders);
        frontTokenBalanceLedger[platformAddress] = frontTokenBalanceLedger[platformAddress].add(toPlatformToken);

        if (toPlatform != 0) {platformAddress.transfer(toPlatform);}

        // 更新买到的Token数量
        frontTokenBalanceLedger[msg.sender] = frontTokenBalanceLedger[msg.sender].add(userTokensBought);
        // 更新玩家具有分红率的Token数量
        dividendTokenBalanceLedger_[msg.sender] = dividendTokenBalanceLedger_[msg.sender].add(userTokensBought.mul(userDividendRate[msg.sender]));
        // 更新分红Token的总量
        divTokenSupply = divTokenSupply.add(userTokensBought.mul(userDividendRate[msg.sender]));

        addOrUpdateHolder(msg.sender);

        // 检查最终结果是否和预期一致
        uint sum = toPlatform + remainingEth + dividendETHAmount - _incomingEther;
        assert(sum == 0);
        sum = toPlatformToken + toReferrer + toTokenHolders + userTokensBought - tokensBought;
        assert(sum == 0);

        emit AssetsDetail(msg.sender, _referredBy, toReferrer, toTokenHolders, toPlatformToken);
        emit Transfer(address(this), msg.sender, userTokensBought);
    }

    /**
     * 一定量的ether能换多少SKC，此方法未扣除平台抽成和股息率部分
     */
    function etherToTokens_(uint _etherAmount)
    public
    view
    returns (uint)
    {
        require(_etherAmount > MIN_ETH_BUYIN, "Tried to buy tokens with too little eth.");

        if (!regularPhase) {
            return _etherAmount.div(TOKEN_PRICE_INITIAL) * 1e18;
        }

        /*
         *  i = investment, p = price, t = number of tokens
         *
         *  i_current = p_initial * t_current                   (for t_current <= t_initial)
         *  i_current = i_initial + (2/3)(t_current)^(3/2)      (for t_current >  t_initial)
         *
         *  t_current = i_current / p_initial                   (for i_current <= i_initial)
         *  t_current = t_initial + ((3/2)(i_current))^(2/3)    (for i_current >  i_initial)
         */

        // First, separate out the buy into two segments:
        //  1) the amount of eth going towards ico-price tokens
        //  2) the amount of eth going towards pyramid-price (variable) tokens
        uint ethTowardsICOPriceTokens = 0;
        uint ethTowardsVariablePriceTokens = 0;

        if (currentEthInvested >= ethInvestedDuringICO) {
            // Option One: All the ETH goes towards variable-price tokens
            ethTowardsVariablePriceTokens = _etherAmount;

        } else if (currentEthInvested < ethInvestedDuringICO && currentEthInvested + _etherAmount <= ethInvestedDuringICO) {
            // Option Two: All the ETH goes towards ICO-price tokens
            ethTowardsICOPriceTokens = _etherAmount;

        } else if (currentEthInvested < ethInvestedDuringICO && currentEthInvested + _etherAmount > ethInvestedDuringICO) {
            // Option Three: Some ETH goes towards ICO-price tokens, some goes towards variable-price tokens
            ethTowardsICOPriceTokens = ethInvestedDuringICO.sub(currentEthInvested);
            ethTowardsVariablePriceTokens = _etherAmount.sub(ethTowardsICOPriceTokens);
        } else {
            // Option Four: Should be impossible, and compiler should optimize it out of existence.
            revert();
        }

        // Sanity check:
        assert(ethTowardsICOPriceTokens + ethTowardsVariablePriceTokens == _etherAmount);

        // Separate out the number of tokens of each type this will buy:
        uint icoPriceTokens = 0;
        uint varPriceTokens = 0;

        // Now calculate each one per the above formulas.
        // Note: since tokens have 18 decimals of precision we multiply the result by 1e18.
        if (ethTowardsICOPriceTokens != 0) {
            icoPriceTokens = ethTowardsICOPriceTokens.mul(1e18).div(TOKEN_PRICE_INITIAL);
        }

        if (ethTowardsVariablePriceTokens != 0) {
            // Note: we can't use "currentEthInvested" for this calculation, we must use:
            //  currentEthInvested + ethTowardsICOPriceTokens
            // This is because a split-buy essentially needs to simulate two separate buys -
            // including the currentEthInvested update that comes BEFORE variable price tokens are bought!

            uint simulatedEthBeforeInvested = toPowerOfThreeHalves(tokenSupply.div(MULTIPLIER * 1e6)).mul(2).div(3) + ethTowardsICOPriceTokens;
            uint simulatedEthAfterInvested = simulatedEthBeforeInvested + ethTowardsVariablePriceTokens;

            /* We have the equations for total tokens above; note that this is for TOTAL.
               To get the number of tokens this purchase buys, use the simulatedEthInvestedBefore
               and the simulatedEthInvestedAfter and calculate the difference in tokens.
               This is how many we get. */

            uint tokensBefore = toPowerOfTwoThirds(simulatedEthBeforeInvested.mul(3).div(2)).mul(MULTIPLIER);
            uint tokensAfter = toPowerOfTwoThirds(simulatedEthAfterInvested.mul(3).div(2)).mul(MULTIPLIER);

            /* Note that we could use tokensBefore = tokenSupply + icoPriceTokens instead of dynamically calculating tokensBefore;
               either should work.

               Investment IS already multiplied by 1e18; however, because this is taken to a power of (2/3),
               we need to multiply the result by 1e6 to get back to the correct number of decimals. */

            varPriceTokens = (1e6) * tokensAfter.sub(tokensBefore);
        }

        uint totalTokensReceived = icoPriceTokens + varPriceTokens;

        assert(totalTokensReceived > 0);
        return totalTokensReceived;
    }

    /**
     * 一定量的SKC能换多少Ether，此方法未扣除平台抽成和股息率部分
     */
    function tokensToEther_(uint _tokens)
    public
    view
    returns (uint)
    {
        require(_tokens >= MIN_TOKEN_SELL_AMOUNT, "Tried to sell too few tokens.");

        /*
         *  i = investment, p = price, t = number of tokens
         *
         *  i_current = p_initial * t_current                   (for t_current <= t_initial)
         *  i_current = i_initial + (2/3)(t_current)^(3/2)      (for t_current >  t_initial)
         *
         *  t_current = i_current / p_initial                   (for i_current <= i_initial)
         *  t_current = t_initial + ((3/2)(i_current))^(2/3)    (for i_current >  i_initial)
         */

        // First, separate out the sell into two segments:
        //  1) the amount of tokens selling at the ICO price.
        //  2) the amount of tokens selling at the variable (pyramid) price
        uint tokensToSellAtICOPrice = 0;
        uint tokensToSellAtVariablePrice = 0;

        if (tokenSupply <= tokensMintedDuringICO) {
            // Option One: All the tokens sell at the ICO price.
            tokensToSellAtICOPrice = _tokens;

        } else if (tokenSupply > tokensMintedDuringICO && tokenSupply - _tokens >= tokensMintedDuringICO) {
            // Option Two: All the tokens sell at the variable price.
            tokensToSellAtVariablePrice = _tokens;

        } else if (tokenSupply > tokensMintedDuringICO && tokenSupply - _tokens < tokensMintedDuringICO) {
            // Option Three: Some tokens sell at the ICO price, and some sell at the variable price.
            tokensToSellAtVariablePrice = tokenSupply.sub(tokensMintedDuringICO);
            tokensToSellAtICOPrice = _tokens.sub(tokensToSellAtVariablePrice);

        } else {
            // Option Four: Should be impossible, and the compiler should optimize it out of existence.
            revert();
        }

        // Sanity check:
        assert(tokensToSellAtVariablePrice + tokensToSellAtICOPrice == _tokens);

        // Track how much Ether we get from selling at each price function:
        uint ethFromICOPriceTokens;
        uint ethFromVarPriceTokens;

        if (tokensToSellAtICOPrice != 0) {

            /* Here, unlike the sister equation in ethereumToTokens, we DON'T need to multiply by 1e18, since
               we will be passed in an amount of tokens to sell that's already at the 18-decimal precision.
               We need to divide by 1e18 or we'll have too much Ether. */

            ethFromICOPriceTokens = tokensToSellAtICOPrice.mul(TOKEN_PRICE_INITIAL).div(1e18);
        }

        if (tokensToSellAtVariablePrice != 0) {

            /* Note: Unlike the sister function in ethereumToTokens, we don't have to calculate any "virtual" token count.
               This is because in sells, we sell the variable price tokens **first**, and then we sell the ICO-price tokens.
               Thus there isn't any weird stuff going on with the token supply.

               We have the equations for total investment above; note that this is for TOTAL.
               To get the eth received from this sell, we calculate the new total investment after this sell.
               Note that we divide by 1e6 here as the inverse of multiplying by 1e6 in ethereumToTokens. */

            uint investmentBefore = toPowerOfThreeHalves(tokenSupply.div(MULTIPLIER * 1e6)).mul(2).div(3);
            uint investmentAfter = toPowerOfThreeHalves((tokenSupply - tokensToSellAtVariablePrice).div(MULTIPLIER * 1e6)).mul(2).div(3);

            ethFromVarPriceTokens = investmentBefore.sub(investmentAfter);
        }

        uint totalEthReceived = ethFromVarPriceTokens + ethFromICOPriceTokens;

        assert(totalEthReceived > 0);
        return totalEthReceived;
    }

    /*=======================
     =   MATHS FUNCTIONS    =
     ======================*/

    function toPowerOfThreeHalves(uint x) public pure returns (uint) {
        // m = 3, n = 2
        // sqrt(x^3)
        return sqrt(x ** 3);
    }

    function toPowerOfTwoThirds(uint x) public pure returns (uint) {
        // m = 2, n = 3
        // cbrt(x^2)
        return cbrt(x ** 2);
    }

    function sqrt(uint x) public pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function cbrt(uint x) public pure returns (uint y) {
        uint z = (x + 1) / 3;
        y = x;
        while (z < y) {
            y = z;
            z = (x / (z * z) + 2 * z) / 3;
        }
    }
}

/*=======================
 =     INTERFACES       =
 ======================*/

library SafeMath {

    function mul(uint a, uint b) internal pure returns (uint) {
        if (a == 0) {
            return 0;
        }
        uint c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint a, uint b) internal pure returns (uint) {
        uint c = a / b;
        return c;
    }

    function sub(uint a, uint b) internal pure returns (uint) {
        assert(b <= a);
        return a - b;
    }

    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        assert(c >= a);
        return c;
    }
}
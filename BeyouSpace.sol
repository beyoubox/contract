pragma solidity ^0.5.8;
 
contract IMigrationContract {
    function migrate(address addr, uint256 nas) public returns (bool success);
}

contract SafeMath {
 
 
    function safeAdd(uint256 x, uint256 y) internal returns(uint256) {
        uint256 z = x + y;
        assert((z >= x) && (z >= y));
        return z;
    }
 
    function safeSubtract(uint256 x, uint256 y) internal returns(uint256) {
        assert(x >= y);
        uint256 z = x - y;
        return z;
    }
 
    function safeMult(uint256 x, uint256 y) internal returns(uint256) {
        uint256 z = x * y;
        assert((x == 0)||(z/x == y));
        return z;
    }
 
}
 
contract Token {
    uint256 public totalSupply;
    function balanceOf(address _owner) public returns (uint256 balance);
    function transfer(address _to, uint256 _value) public returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
    function approve(address _spender, uint256 _value) public returns (bool success);
    function allowance(address _owner, address _spender) public returns (uint256 remaining);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}
 
 
/*  ERC 20 token */
contract StandardToken is Token {
 
    function transfer(address _to, uint256 _value) public returns (bool success) {
        if (balances[msg.sender]-locks[msg.sender] >= _value && _value > 0&&balances[_to]+_value>=balances[_to]) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            emit Transfer(msg.sender, _to, _value);
            return true;
        } else {
            return false;
        }
    }
 
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        if (balances[_from]-locks[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0&&balances[_to]+_value>=balances[_to]) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            emit Transfer(_from, _to, _value);
            return true;
        } else {
            return false;
        }
    }
 
    function balanceOf(address _owner) public returns (uint256 balance) {
        return balances[_owner];
    }
 
    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }
 
    function allowance(address _owner, address _spender) public returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }
 
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
    mapping (address => uint256) locks;
}
 
contract DataCoin is StandardToken, SafeMath {
 
    // metadata
    string  public constant name = "Beyoucoin";
    string  public constant symbol = "BYC";
    uint256 public constant decimals = 18;
    string  public version = "1.0";
 
    // contracts
    address payable public ethFundDeposit;          // ETH存放地址
    address public newContractAddr;         // token更新地址
 
    // crowdsale parameters
    bool    public isFunding;                // 状态切换到true
    uint256 public fundingStartBlock;
    uint256 public fundingStopBlock;
 
    uint256 public currentSupply;           // 正在售卖中的tokens数量
    uint256 public tokenRaised = 0;         // 总的售卖数量token
    uint256 public tokenMigrated = 0;     // 总的已经交易的 token
    uint256 public tokenExchangeRate = 1000;             // 1000 DTC 兑换 1 ETH
 
    // events
    event AllocateToken(address indexed _to, uint256 _value);   // 分配的私有交易token;
    event IssueToken(address indexed _to, uint256 _value);      // 公开发行售卖的token;
    event IncreaseSupply(uint256 _value);
    event DecreaseSupply(uint256 _value);
    event Migrate(address indexed _to, uint256 _value);
 
    // 转换
    function formatDecimals(uint256 _value) internal returns (uint256 ) {
        return _value * 10 ** decimals;
    }
 
    // constructor
    constructor(
        address payable _ethFundDeposit) public
    {
        ethFundDeposit = _ethFundDeposit;
 
        isFunding = false;                           //通过控制预CrowdSale状态
        fundingStartBlock = 0;
        fundingStopBlock = 0;
 
        totalSupply = formatDecimals(19960312*40*100000000);
        currentSupply = totalSupply/2;
        balances[msg.sender] = totalSupply;
        if(currentSupply > totalSupply) revert();
    }

  function lock(address _addr, uint256 _value) public {
    uint256 value = formatDecimals(_value);
    if(balances[_addr]>=safeAdd(locks[_addr],value)){
        locks[_addr]+=value;
    }else{
        revert();
    }
  }

  function unlock(address _addr, uint256 _value) public {
    uint256 value = formatDecimals(_value);
    if(locks[_addr]>=value){
        locks[_addr]-=value;
    }else{
        revert();
    }
  }
 
    modifier isOwner()  { require(msg.sender == ethFundDeposit); _; }
 
    ///  设置token汇率
    function setTokenExchangeRate(uint256 _tokenExchangeRate) isOwner external {
        if (_tokenExchangeRate == 0) revert();
        if (_tokenExchangeRate == tokenExchangeRate) revert();
 
        tokenExchangeRate = _tokenExchangeRate;
    }
 
    /// @dev 超发token处理
    function increaseSupply (uint256 _value) isOwner external {
        uint256 value = formatDecimals(_value);
        if (value + currentSupply > totalSupply) revert();
        currentSupply = safeAdd(currentSupply, value);
        emit IncreaseSupply(value);
    }
 
    /// @dev 被盗token处理
    function decreaseSupply (uint256 _value) isOwner external {
        uint256 value = formatDecimals(_value);
        if (value + tokenRaised > currentSupply) revert();
 
        currentSupply = safeSubtract(currentSupply, value);
        emit DecreaseSupply(value);
    }
 
    ///  启动区块检测 异常的处理
    function startFunding (uint256 _fundingStartBlock, uint256 _fundingStopBlock) isOwner external {
        if (isFunding) revert();
        if (_fundingStartBlock >= _fundingStopBlock) revert();
        if (block.number >= _fundingStartBlock) revert();
 
        fundingStartBlock = _fundingStartBlock;
        fundingStopBlock = _fundingStopBlock;
        isFunding = true;
    }
 
    ///  关闭区块异常处理
    function stopFunding() isOwner external {
        if (!isFunding) revert();
        isFunding = false;
    }
 
    /// 开发了一个新的合同来接收token（或者更新token）
    function setMigrateContract(address _newContractAddr) isOwner external {
        if (_newContractAddr == newContractAddr) revert();
        newContractAddr = _newContractAddr;
    }
 
    /// 设置新的所有者地址
    function changeOwner(address payable _newFundDeposit) isOwner() external {
        if (_newFundDeposit == address(0x0)) revert();
        ethFundDeposit = _newFundDeposit;
    }
 
    ///转移token到新的合约
    function migrate() external {
        if(isFunding) revert();
        if(newContractAddr == address(0x0)) revert();
 
        uint256 tokens = balances[msg.sender];
        if (tokens == 0) revert();
 
        balances[msg.sender] = 0;
        tokenMigrated = safeAdd(tokenMigrated, tokens);
 
        IMigrationContract newContract = IMigrationContract(newContractAddr);
        if (!newContract.migrate(msg.sender, tokens)) revert();
 
        emit Migrate(msg.sender, tokens);               // log it
    }
 
    /// 转账ETH 到数据币团队
    function transferETH() isOwner external {
        if (address(this).balance == 0) revert();
        if (!ethFundDeposit.send(address(this).balance)) revert();
    }
 
    /// 购买token
    function () external payable {
        if (!isFunding) revert();
        if (msg.value == 0) revert();
 
        if (block.number < fundingStartBlock) revert();
        if (block.number > fundingStopBlock) revert();
 
        uint256 tokens = safeMult(msg.value, tokenExchangeRate);
        if (tokens + tokenRaised > currentSupply) revert();
 
        tokenRaised = safeAdd(tokenRaised, tokens);

        transferFrom(ethFundDeposit,msg.sender,tokens);
 
        emit IssueToken(msg.sender, tokens);  //记录日志
    }
}
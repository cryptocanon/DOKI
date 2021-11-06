// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract FLOKI is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    uint256 public _tax;
    uint256 private _prevTax = _tax;
	
	mapping(address => uint256) private _totalOwned;
	mapping(address => uint256) private _refOwned;
	
	mapping(address => mapping(address => uint256)) private _allocations;
    mapping(address => bool) private _isBot;
    address[] private _confirmedBots;
	
	mapping(address => bool) private _isEliminatedFromFee;
    mapping(address => bool) private _isEliminated;
    address[] private _eliminated;
	
	address payable public marketingAddress =
    payable(0x83132E0b3a2bbef6Bf3a7b7533cFdBbc7C1F7708);
    address public immutable burnAddress =
    0x000000000000000000000000000000000000dEaD;
    
	string private _name = 'DogeFlokiOfficial';
    string private _symbol = 'DOGEFLOKI';
    uint8 private _decimals = 9;
	
	uint256 public _liquidityFee = 4;
    uint256 private _previousLiquidityFee = _liquidityFee;
	
	uint256 private _feeRate = 4;
    
	uint256 private constant MAX = ~uint256(0);
    uint256 private _totalSupply = 10000000000000 * 10**9;
    uint256 private _refSupply = (MAX - (MAX % _totalSupply));
    uint256 private _totalFees;
	
	uint256 launchTime;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    bool liquidityFlag;

    bool tradingOpen = false;

    event SwapETHForTokens(uint256 amountIn, address[] path);

    event SwapTokensForETH(uint256 amountIn, address[] path);

    modifier lockTheSwap() {
        liquidityFlag = true;
        _;
        liquidityFlag = false;
    }

    constructor() {
        _refOwned[_msgSender()] = _refSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    function initContract() external onlyOwner {
        // PancakeSwap: 0x10ED43C718714eb63d5aA57B78B54704E256024E
        // Uniswap V2: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WETH()
        );

        uniswapV2Router = _uniswapV2Router;

        _isEliminatedFromFee[owner()] = true;
        _isEliminatedFromFee[address(this)] = true;
    }

    function openTrading() external onlyOwner {
        _liquidityFee = _previousLiquidityFee;
        _tax = _prevTax;
        tradingOpen = true;
        launchTime = block.timestamp;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isEliminated[account]) return _totalOwned[account];
        return tokenFromReflection(_refOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    )
        public
        view
        override
        returns (uint256)
    {
        return _allocations[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    )
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        override
        returns (bool)
    {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allocations[sender][_msgSender()].sub(
                amount,
                'Insufficient allowance amount for the transfer'
            )
        );
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    )
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allocations[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
    public
    virtual
    returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allocations[_msgSender()][spender].sub(
                subtractedValue,
                'Subtracted allowance below zero'
            )
        );
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isEliminated[account];
    }

    function totalFees() public view returns (uint256) {
        return _totalFees;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !_isEliminated[sender],
            'This function cannot be called by eliminated addresses'
        );
        (uint256 rAmount, , , , , ) = _getValues(tAmount);
        _refOwned[sender] = _refOwned[sender].sub(rAmount);
        _refSupply = _refSupply.sub(rAmount);
        _totalFees = _totalFees.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
    public
    view
    returns (uint256)
    {
        require(tAmount <= _totalSupply, 'total Amount should not exceed total supply');
        if (!deductTransferFee) {
            (uint256 rAmount, , , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
        require(rAmount <= _refSupply, ' Reflection Amount should not exceed total reflections');
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!_isEliminated[account], 'Account is already excluded');
        if (_refOwned[account] > 0) {
            _totalOwned[account] = tokenFromReflection(_refOwned[account]);
        }
        _isEliminated[account] = true;
        _eliminated.push(account);
    }

    function includeInReward(address account) external onlyOwner {
        require(_isEliminated[account], 'Account is already excluded');
        for (uint256 i = 0; i < _eliminated.length; i++) {
            if (_eliminated[i] == account) {
                _eliminated[i] = _eliminated[_eliminated.length - 1];
                _totalOwned[account] = 0;
                _isEliminated[account] = false;
                _eliminated.pop();
                break;
            }
        }
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), 'ERC20: approve from the zero address');
        require(spender != address(0), 'ERC20: approve to the zero address');

        _allocations[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), 'ERC20: transfer from the zero address');
        require(to != address(0), 'ERC20: transfer to the zero address');
        require(amount > 0, 'Transfer amount must be greater than zero');
        require(!_isBot[to], 'You got busted!');
        require(!_isBot[msg.sender], 'You got busted!');

        // buy
        if (
            from == uniswapV2Pair &&
            to != address(uniswapV2Router) &&
            !_isEliminatedFromFee[to]
        ) {
            require(tradingOpen, 'Trading not yet open.');

            //antibot
            if (block.timestamp == launchTime) {
                _isBot[to] = true;
                _confirmedBots.push(to);
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        //sell

        if (!liquidityFlag && tradingOpen && to == uniswapV2Pair) {
            if (contractTokenBalance > 0) {
                if (
                    contractTokenBalance > balanceOf(uniswapV2Pair).mul(_feeRate).div(100)
                ) {
                    contractTokenBalance = balanceOf(uniswapV2Pair).mul(_feeRate).div(
                        100
                    );
                }
                swapTokens(contractTokenBalance);
            }
        }

        bool takeFee = false;

        //take fee only on swaps
        if (
            (from == uniswapV2Pair || to == uniswapV2Pair) &&
            !(_isEliminatedFromFee[from] || _isEliminatedFromFee[to])
        ) {
            takeFee = true;
        }

        _tokenTransfer(from, to, amount, takeFee);
    }

    function swapTokens(uint256 contractTokenBalance) private lockTheSwap {
        swapTokensForEth(contractTokenBalance);

        //Send to Marketing address
        uint256 contractETHBalance = address(this).balance;
        if (contractETHBalance > 0) {
            sendETHToMarketing(address(this).balance);
        }
    }

    function sendETHToMarketing(uint256 amount) private {
        // Ignore the boolean return value. If it gets stuck, then retrieve via `emergencyWithdraw`.
        marketingAddress.call{value: amount}("");
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this), // The contract
            block.timestamp
        );

        emit SwapTokensForETH(tokenAmount, path);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{ value: ethAmount }(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        if (_isEliminated[sender] && !_isEliminated[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isEliminated[sender] && _isEliminated[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isEliminated[sender] && _isEliminated[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
        uint256 rAmount,
        uint256 rTransferAmount,
        uint256 rFee,
        uint256 tTransferAmount,
        uint256 tFee,
        uint256 tLiquidity
        ) = _getValues(tAmount);
        _refOwned[sender] = _refOwned[sender].sub(rAmount);
        _refOwned[recipient] = _refOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
        uint256 rAmount,
        uint256 rTransferAmount,
        uint256 rFee,
        uint256 tTransferAmount,
        uint256 tFee,
        uint256 tLiquidity
        ) = _getValues(tAmount);
        _refOwned[sender] = _refOwned[sender].sub(rAmount);
        _totalOwned[recipient] = _totalOwned[recipient].add(tTransferAmount);
        _refOwned[recipient] = _refOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
        uint256 rAmount,
        uint256 rTransferAmount,
        uint256 rFee,
        uint256 tTransferAmount,
        uint256 tFee,
        uint256 tLiquidity
        ) = _getValues(tAmount);
        _totalOwned[sender] = _totalOwned[sender].sub(tAmount);
        _refOwned[sender] = _refOwned[sender].sub(rAmount);
        _refOwned[recipient] = _refOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
        uint256 rAmount,
        uint256 rTransferAmount,
        uint256 rFee,
        uint256 tTransferAmount,
        uint256 tFee,
        uint256 tLiquidity
        ) = _getValues(tAmount);
        _totalOwned[sender] = _totalOwned[sender].sub(tAmount);
        _refOwned[sender] = _refOwned[sender].sub(rAmount);
        _totalOwned[recipient] = _totalOwned[recipient].add(tTransferAmount);
        _refOwned[recipient] = _refOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _refSupply = _refSupply.sub(rFee);
        _totalFees = _totalFees.add(tFee);
    }

    function _getValues(uint256 tAmount)
    private
    view
    returns (
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256
    )
    {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(
            tAmount
        );
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tFee,
            tLiquidity,
            _getRate()
        );
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
    }

    function _getTValues(uint256 tAmount)
    private
    view
    returns (
        uint256,
        uint256,
        uint256
    )
    {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
        return (tTransferAmount, tFee, tLiquidity);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tLiquidity,
        uint256 currentRate
    )
    private
    pure
    returns (
        uint256,
        uint256,
        uint256
    )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _refSupply;
        uint256 tSupply = _totalSupply;
        for (uint256 i = 0; i < _eliminated.length; i++) {
            if (_refOwned[_eliminated[i]] > rSupply || _totalOwned[_eliminated[i]] > tSupply)
                return (_refSupply, _totalSupply);
            rSupply = rSupply.sub(_refOwned[_eliminated[i]]);
            tSupply = tSupply.sub(_totalOwned[_eliminated[i]]);
        }
        if (rSupply < _refSupply.div(_totalSupply)) return (_refSupply, _totalSupply);
        return (rSupply, tSupply);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate = _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _refOwned[address(this)] = _refOwned[address(this)].add(rLiquidity);
        if (_isEliminated[address(this)])
            _totalOwned[address(this)] = _totalOwned[address(this)].add(tLiquidity);
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_tax).div(10**2);
    }

    function calculateLiquidityFee(uint256 _amount)
    private
    view
    returns (uint256)
    {
        return _amount.mul(_liquidityFee).div(10**2);
    }

    function removeAllFee() private {
        if (_tax == 0 && _liquidityFee == 0) return;

        _prevTax = _tax;
        _previousLiquidityFee = _liquidityFee;

        _tax = 0;
        _liquidityFee = 0;
    }

    function restoreAllFee() private {
        _tax = _prevTax;
        _liquidityFee = _previousLiquidityFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isEliminatedFromFee[account];
    }

    function excludeFromFee(address account) public onlyOwner {
        _isEliminatedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isEliminatedFromFee[account] = false;
    }

    function setTaxFeePercent(uint256 taxFee) external onlyOwner {
        _tax = taxFee;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        _liquidityFee = liquidityFee;
    }

    function setMarketingAddress(address _marketingAddress) external onlyOwner {
        marketingAddress = payable(_marketingAddress);
    }

    function transferToAddressETH(address payable recipient, uint256 amount)
    private
    {
        recipient.transfer(amount);
    }

    function isRemovedSniper(address account) public view returns (bool) {
        return _isBot[account];
    }

    function _removeSniper(address account) external onlyOwner {
        require(
            account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
            'We can not blacklist Uniswap'
        );
        require(!_isBot[account], 'Account is already blacklisted');
        _isBot[account] = true;
        _confirmedBots.push(account);
    }

    function _amnestySniper(address account) external onlyOwner {
        require(_isBot[account], 'Account is not blacklisted');
        for (uint256 i = 0; i < _confirmedBots.length; i++) {
            if (_confirmedBots[i] == account) {
                _confirmedBots[i] = _confirmedBots[_confirmedBots.length - 1];
                _isBot[account] = false;
                _confirmedBots.pop();
                break;
            }
        }
    }

    function setFeeRate(uint256 rate) external onlyOwner {
        _feeRate = rate;
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    // Withdraw ETH that gets stuck in contract by accident
    function emergencyWithdraw() external onlyOwner {
        payable(owner()).send(address(this).balance);
    }
}

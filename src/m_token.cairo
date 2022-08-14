%lang starknet

from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_lt
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.uint256 import Uint256, uint256_check, uint256_eq, uint256_not

from openzeppelin.token.erc20.library import ERC20
from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.access.ownable.library import Ownable
from openzeppelin.security.safemath.library import SafeUint256
from openzeppelin.utils.constants.library import UINT8_MAX
from starkware.starknet.common.syscalls import get_block_timestamp

# 
# Storage
# 
@storage_var
func underlying_token_addr() -> (address : felt):
end

# 
# Contructor
# 
@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    name: felt, symbol: felt, owner: felt,  token_addr: felt
):
    ERC20.initializer(name, symbol, 18)
    Ownable.initializer(owner)
    underlying_token_addr.write(token_addr)
    return ()
end

#
# Views
#

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
    let (name) = ERC20.name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt):
    let (symbol) = ERC20.symbol()
    return (symbol)
end

@view
func total_supply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    totalSupply : Uint256
):
    let (totalSupply : Uint256) = ERC20.total_supply()
    return (totalSupply)
end

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    decimals : felt
):
    let (decimals) = ERC20.decimals()
    return (decimals)
end

@view
func balance_of{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt
) -> (balance : Uint256):
    let (balance : Uint256) = ERC20.balance_of(account)
    return (balance)
end

@view
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, spender : felt
) -> (remaining : Uint256):
    let (remaining : Uint256) = ERC20.allowance(owner, spender)
    return (remaining)
end


#
# Externals
#

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount : Uint256
) -> (success : felt):
    ERC20.transfer(recipient, amount)
    return (1)
end

@external
func transfer_from{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender : felt, recipient : felt, amount : Uint256
) -> (success : felt):
    ERC20.transfer_from(sender, recipient, amount)
    return (1)
end

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, amount : Uint256
) -> (success : felt):
    ERC20.approve(spender, amount)
    return (1)
end

@external
func increase_allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, added_value : Uint256
) -> (success : felt):
    ERC20.increase_allowance(spender, added_value)
    return (1)
end

@external
func decreaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, subtracted_value : Uint256
) -> (success : felt):
    ERC20.decrease_allowance(spender, subtracted_value)
    return (1)
end



# 
# Wrapping related logics
# 
@external
func wrap{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(to: felt, amount: Uint256):
        let (token_addr) = underlying_token_addr.read()
        let (caller) = get_caller_address()
        
        let (transfer_res) = IERC20.transferFrom(
            contract_address=token_addr,
            sender=caller,
            recipient=to,
            amount=amount
        )
        with_attr error_message("Wrapping failed, cannot transfer ERC20 to contract."):
            assert transfer_res = 1
        end

        ERC20._mint(to, amount)
        return ()
end

@external
func unwrap{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt, amount: Uint256):
        ERC20._burn(account, amount)
        
        let (token_addr) = underlying_token_addr.read()
        let (m_token_contract) = get_contract_address()
        let (caller) = get_caller_address()
        
        let (transfer_res) = IERC20.transferFrom(
            contract_address=token_addr,
            sender=m_token_contract,
            recipient=caller,
            amount=amount
        )
        with_attr error_message("Unwrapping failed."):
            assert transfer_res = 1
        end

        return ()
end

#####################################################################

struct inflow:
    member Index: felt
    member amount_per_unit: felt
    member createdTimestamp: felt
end

struct outflow:
    member Index: felt
    member amount_per_unit: felt
    member createdTimestamp: felt
end
# stream_in_length_by_address: account->total len of inflow array
@storage_var
func stream_in_len_by_addr(account:felt) -> (res: felt):
end

# stream_in_info_by_address: (account:felt)-> (array_of_struct: inflow*)
@storage_var
func stream_in_info_by_addr(account:felt) -> (res : inflow*):
end


@storage_var
func stream_out_len_by_addr(account:felt) -> (res : felt):
end

@storage_var
func stream_out_info_by_addr(account:felt) -> (res : outflow*):
end



# Get current net balance
@view
func getBalance{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt)->(totalBalance:Uint256):
    # static balance
    let (static_balance: Uint256)= balance_of(account)

    # dynamic balance

    # inflow
    let (len_in:felt)= stream_in_len_by_addr.read(account)

    let (inflow_sum: Uint256) = getInflowSum(len_in,stream_in_info_by_addr.read(account))



    # outflow
    let (len_out:felt)= stream_out_len_by_addr.read(account)
    let (outflow_sum:Uint256) = getOutflowSum(len_out, stream_out_info_by_addr.read(account))


    let (totalBalance) = static_balance + inflow_sum - outflow_sum
    return (totalBalance)
end

# TODO: modify logic
@view
func getInflowSum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(n:felt,arr: inflow*)->(res: Uint256):
    if n==1:
        let (block_timestamp) = get_block_timestamp()
        let result= (arr[n-1].amount_per_unit*(block_timestamp-arr[n-1].createdTimestamp))/86400
        return (result)
    end
    return getInflowSum(n-1,arr[n])
    
end
# TODO: modify logic
@view
func getOutflowSum{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(n:felt,arr: outflow*)->(res: Uint256):
    if n==1:
        let (block_timestamp) = get_block_timestamp()
        let result= (arr[n-1].amount_per_unit*(block_timestamp-arr[n-1].createdTimestamp))/86400
        return (result)
    end
    return getOutflowSum(n-1,arr[n])
end

######################################################################
# called by core contract when a new stream is created 
# update sender's outflow and receiver's inflow
@external
func Stream_created{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(sender:felt,receiver:felt,amount:Uint256,createdTimestamp:felt)->(bool:felt):
    # get and update receiver inflow info 
    let (len_in:felt) = stream_in_len_by_addr.read(receiver)

    stream_in_info_by_address.write(receiver,inflow[len_in]=inflow(index= len_in,amount_per_unit= amount,createdTimestamp=createdTimestamp))
    
    
    stream_in_len_by_addr.write(receiver,len_in+1) 

    # get and update sender outlow info 
    let len_out=stream_out_len_by_addr(sender)
    stream_out_info_by_addr.write(sender,outflow[len_out]=outflow(index=len_out,amount_per_unit= amount,createdTimestamp=createdTimestamp))
        

    stream_out_len_by_addr.write(sender,len_out+1)

    return true
end

#####################################################################
# called by core contract when a new stream is stopped 
# update sender's outflow and receiver's inflow
@external
func Stream_stopped{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(sender:felt,receiver:felt,amount:Uint256,createdTimestamp:felt)->(bool:felt):
    # get and update receiver inflow info 
    stream_in_length_by_address: receiver->total len of inflow array
    let (len_in:felt)= stream_in_len_by_addr.read(receiver)
    # TODO: change the for loop
    # for index = range(len_in):
    #     # a dumb way
    #     if(stream_in_info_by_addr(receiver)[index].amount_per_unit == amount
    #     && stream_in_info_by_addr(receiver)[index].createdTimestamp == createdTimestamp)
    #     let stream_in_info_by_addr(receiver)[index].amount_per_unit = 0
    let (inflow: inflow*) = stream_in_info_by_addr.read(receiver)
    findInflowStream(len_in,inflow,amount,createdTimestamp)
    # get and update sender outlow info 
    let (len_out:felt)=stream_out_len_by_addr.read(sender)
    # for index = range(len_out):
    #     # a dumb way
    #     if(stream_out_info_by_address(sender)[index].amount_per_unit == amount
    #     && stream_out_info_by_address(sender)[index].createdTimestamp == createdTimestamp)
    #     let stream_out_info_by_address(sender)[index].amount_per_unit== 0
    let (outflow: outflow*) = stream_out_info_by_addr.read(sender)
    findOutflowStream(len_out,outflow,amount,createdTimestamp)
    return true
end

@external
func findInflowStream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    len:Uint256,
    arr: inflow*,
    amount: Uint256,
    createdTimestamp: felt
):
    if arr[len-1].amount_per_unit == amount && arr[len-1].createdTimestamp == createdTimestamp:
        arr[len-1].amount_per_unit = 0
    end
    return findInflowStream(len-1,arr,amount,createdTimestamp)
end
@external
func findOutflowStream{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    len:Uint256,
    arr: outflow*,
    amount: Uint256,
    createdTimestamp: felt
):
    if arr[len-1].amount_per_unit == amount && arr[len-1].createdTimestamp == createdTimestamp:
        arr[len-1].amount_per_unit = 0
    end
    return findOutflowStream(len-1,arr,amount,createdTimestamp)
end
####################################################################################

#TODO: consider negative part

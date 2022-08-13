# SPDX-License-Identifier: MIT
# OpenZeppelin Contracts for Cairo v0.3.1 (token/erc20/library.cairo)

%lang starknet

from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_not_zero, assert_lt
from starkware.cairo.common.bool import FALSE
from starkware.cairo.common.uint256 import Uint256, uint256_check, uint256_eq, uint256_not

from openzeppelin.token.erc20.library import ERC20
from openzeppelin.security.safemath.library import SafeUint256
from openzeppelin.utils.constants.library import UINT8_MAX
from starkware.starknet.common.syscalls import get_block_timestamp
# 
# Contructor
# 
@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    name: felt, symbol: felt
):
    ERC20.initializer(name, symbol, 18)
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
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, spender : felt
) -> (remaining : Uint256):
    let (remaining : Uint256) = ERC20.allowance(owner, spender)
    return (remaining)
end


func balance_of{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt) -> (balance: Uint256):
    let (balance: Uint256) = ERC20_balances.read(account)
    return (balance)
end

func transfer{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(recipient: felt, amount: Uint256):
    let (sender) = get_caller_address()
    _transfer(sender, recipient, amount)
    return ()
end

func transfer_from{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        sender: felt,
        recipient: felt,
        amount: Uint256
    ) -> ():
    let (caller) = get_caller_address()
    # subtract allowance
    _spend_allowance(sender, caller,  amount)
    # execute transfer
    _transfer(sender, recipient, amount)
    return ()
end

func approve{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(spender: felt, amount: Uint256):
    with_attr error_message("ERC20: amount is not a valid Uint256"):
        uint256_check(amount)
    end

    let (caller) = get_caller_address()
    _approve(caller, spender, amount)
    return ()
end


# 
# Wrapping related logics
# 

func deposit{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }
end


func deposit{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }
end
#
# Internal
#


func _transfer{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(sender: felt, recipient: felt, amount: Uint256):
    with_attr error_message("ERC20: amount is not a valid Uint256"):
        uint256_check(amount) # almost surely not needed, might remove after confirmation
    end

    with_attr error_message("ERC20: cannot transfer from the zero address"):
        assert_not_zero(sender)
    end

    with_attr error_message("ERC20: cannot transfer to the zero address"):
        assert_not_zero(recipient)
    end

    let (sender_balance: Uint256) = ERC20_balances.read(account=sender)
    with_attr error_message("ERC20: transfer amount exceeds balance"):
        let (new_sender_balance: Uint256) = SafeUint256.sub_le(sender_balance, amount)
    end

    ERC20_balances.write(sender, new_sender_balance)

    # add to recipient
    let (recipient_balance: Uint256) = ERC20_balances.read(account=recipient)
    # overflow is not possible because sum is guaranteed by mint to be less than total supply
    let (new_recipient_balance: Uint256) = SafeUint256.add(recipient_balance, amount)
    ERC20_balances.write(recipient, new_recipient_balance)
    Transfer.emit(sender, recipient, amount)
    return ()
end

func _approve{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(owner: felt, spender: felt, amount: Uint256):
    with_attr error_message("ERC20: amount is not a valid Uint256"):
        uint256_check(amount)
    end

    with_attr error_message("ERC20: cannot approve from the zero address"):
        assert_not_zero(owner)
    end

    with_attr error_message("ERC20: cannot approve to the zero address"):
        assert_not_zero(spender)
    end

    ERC20_allowances.write(owner, spender, amount)
    Approval.emit(owner, spender, amount)
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
func getBalance
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(account: felt):
# static balance
let (static_balance: Uint256)= balance_of(account)

# dynamic balance

# inflow
let (len_in:felt)= stream_in_len_by_addr.read(account)

let (inflow_sum: felt) = getInflowSum(len_in,stream_in_info_by_addr.read(account))



# outflow
let (len_out:felt)= stream_out_len_by_addr.read(account_
let (outflow_sum:felt_ = getOutflowSum(len_out, stream_out_info_by_addr.read(account))


return totalBalance = static_balance + inflow_sum - outflow_sum

# TODO: modify logic
func getInflowSum(n:felt,arr: inflow*)->(res: felt):
    if n==1:
        let (block_timestamp_ = get_block_timestamp()
        let result= (arr[n-1].amount_per_unit*block_timestamp)/(arr[n-1].createdTimestamp)
        return result
    return getInflowSum(n-1,arr[n])

# TODO: modify logic
func getOutflowSum(n:felt,arr: outflow*)->(res: felt):
    if n==1:
        let (block_timestamp_ = get_block_timestamp()
        let result= (arr[n-1].amount_per_unit*block_timestamp)/(arr[n-1].createdTimestamp)
        return result
    return getOutflowSum(n-1,arr[n])



######################################################################
# called by core contract when a new stream is created 
# update sender's outflow and receiver's inflow
func Stream_created(sender,receiver,amount,createdTimestamp)->:
    # get and update receiver inflow info 
    let (len_in:felt) = stream_in_len_by_addr.read(receiver)

    assert stream_in_info_by_address.read(receiver)[len_in]= 
    inflow(index= len_in,amount_per_unit= amount,createdTimestamp=c reatedTimestamp)
    
    assert stream_in_len_by_addr.read(receiver) = len_in+1

    # get and update sender outlow info 
    let len_out=stream_out_len_by_addr(sender)
    assert stream_out_info_by_addr.read(sender)[len_out]= 
        outflow(index=len_out,amount_per_unit= amount,createdTimestamp=createdTimestamp)

    assert stream_out_len_by_addr.read(sender) = len_out+1

    return true
#####################################################################
# called by core contract when a new stream is stopped 
# update sender's outflow and receiver's inflow
func Stream_stopped(sender,receiver,amount,createdTimestamp)->bool:
    # get and update receiver inflow info 
    stream_in_length_by_address: receiver->total len of inflow array
    let (len_in:felt)= stream_in_len_by_addr.read(receiver)
    # TODO: change the for loop
    for index = range(len_in):
        # a dumb way
        if(stream_in_info_by_addr(receiver)[index].amount_per_unit == amount
        && stream_in_info_by_addr(receiver)[index].createdTimestamp == createdTimestamp)
        let stream_in_info_by_addr(receiver)[index].amount_per_unit = 0

    # get and update sender outlow info 
    let (len_out:felt)=stream_out_len_by_addr.read(sender)
    for index = range(len_out):
        # a dumb way
        if(stream_out_info_by_address(sender)[index].amount_per_unit == amount
        && stream_out_info_by_address(sender)[index].createdTimestamp == createdTimestamp)
        let stream_out_info_by_address(sender)[index].amount_per_unit== 0
####################################################################################

TODO: consider negative part

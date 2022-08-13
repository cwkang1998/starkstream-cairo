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
for index=range(streams_in_length_by_address_to_len(account)) #return len of total in stream
    
    # stream amount*(timestamp now - createdtimestamp)/86400  (per day)
    stream_amount = stream_in_info_by_address(account)[index].amount_per_day
    timepassed_in_day = (timestampnow-stream_in_info_by_address(account)[index].createdTimestamp)/86400
    if is_stop != FALSE:
        inflow+= stream_amount*timepassed_in_day

# outflow
for index=range(streams_out_length_by_address_to_len(account)) #return len of total in stream
    
    # stream amount*(timestamp now - createdtimestamp)/86400  (per day)
    stream_amount = stream_out_info_by_address(account)[index].amount_per_day
    timepassed_in_day = (timestampnow-stream_out_info_by_address(account)[index].createdTimestamp)/86400
    if is_stop != FALSE:
        outflow+= stream_amount*timepassed_in_day

return totalBalance = static_balance + inflow - outflow


struct inflow/outflow{
    index: Uint256,
    amount_per_day: uint256,
    createdTimestamp: block.timestamp,
    is_stop: bool
}
# mapping
# in flow
# stream_in_length_by_address: account->total len of inflow array
# stream_in_info_by_address: (account:felt)-> (array_of_struct: inflow*)
# outflow
# stream_out_length_by_address: account->total  len of outflow array
# stream_out_info_by_address: (account:felt)->(array_of_struct: outflow*)


######################################################################
# called by core contract when a new stream is created 
# update sender's outflow and receiver's inflow
func Stream_created(sender,receiver,amount,createdTimestamp)->:
    # get and update receiver inflow info 
    stream_in_length_by_address: receiver->total len of inflow array
    len_in= (stream_in_length_by_address)
    stream_in_info_by_address(receiver).push(
        inflow(index= len_in,amount_per_day=amount,createdTimestamp=createdTimestamp, is_stop=FALSE)
    )
    stream_in_length_by_address(receiver)+=1
    # get and update sender outlow info 
    len_out=stream_out_length_by_address(account)
    stream_out_info_by_address(sender).push(
        outflow(index=len_out,amount_per_day=amount,createdTimestamp=createdTimestamp,is_stop=FALSE)

    )
    stream_out_length_by_address(sender)+=1
    return true
#####################################################################
# called by core contract when a new stream is stopped 
# update sender's outflow and receiver's inflow
func Stream_stopped(sender,receiver,amount,createdTimestamp)->bool:
    # get and update receiver inflow info 
    stream_in_length_by_address: receiver->total len of inflow array
    len_in= (stream_in_length_by_address)
    for index = range(len_in):
        # a dumb way
        if(stream_in_info_by_address(receiver)[index].amount_per_day == amount
        && stream_in_info_by_address(receiver)[index].createdTimestamp == createdTimestamp
        && stream_in_info_by_address(receiver)[index].is_stop == FALSE):
        let stream_in_info_by_address(receiver)[index].is_stop == TRUE

    # get and update sender outlow info 
    len_out=stream_out_length_by_address(account)
    for index = range(len_out):
        # a dumb way
        if(stream_out_info_by_address(sender)[index].amount_per_day == amount
        && stream_out_info_by_address(sender)[index].createdTimestamp == createdTimestamp
        && stream_out_info_by_address(sender)[index].is_stop == FALSE):
        let stream_out_info_by_address(sender)[index].is_stop == TRUE
####################################################################################

TODO: consider negative part

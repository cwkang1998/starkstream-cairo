%lang starknet
from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace Im_token:
    func get_underlying_token_addr() -> (res: felt):
    end

    func get_owner() -> (res: felt):
    end

    func wrap(amount : Uint256):
    end

    func approve(spender: felt, amount: Uint256):
    end
end
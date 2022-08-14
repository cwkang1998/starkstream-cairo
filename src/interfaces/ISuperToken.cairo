%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (Uint256)

@contract_interface
namespace ISuperToken:
    # ERC20MintableBurnable
    ## view
    func name() -> (res: felt):
    end
    func symbol() -> (res: felt):
    end
    func totalSupply() -> (res: felt):
    end
    func decimals() -> (res: felt):
    end
    func balanceOf() -> (res: felt):
    end
    func allowance() -> (res: felt):
    end
    func owner() -> (res: felt):
    end
    ## external
    func mint(recipient: felt, amount: Uint256) -> (res: felt):
    end   
    func burn(account: felt, amount: Uint256) -> (res: felt):
    end   
end
%lang starknet
from starkware.cairo.common.uint256 import Uint256
from src.structs.m_token_struct import inflow, outflow

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

    func start_stream(
        recipient : felt, amount_per_second : Uint256, deposit_amount: Uint256
    ):
    end

    func get_all_outflow_streams_by_user(
        user: felt
    ) -> (res_len: felt, res: outflow*):
    end

    func get_all_inflow_streams_by_user(
        user: felt
    ) -> (res_len: felt, res: inflow*):
    end
end
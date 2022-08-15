%lang starknet

from starkware.cairo.common.uint256 import Uint256

struct inflow:
    member index : felt
    member amount_per_second : Uint256
    member created_timestamp : felt
    member to : felt
    member from_sender : felt
    member outflow_index : felt
    member deposit : Uint256
end

struct outflow:
    member index : felt
    member amount_per_second : Uint256
    member created_timestamp : felt
    member to : felt
    member from_sender : felt
    member inflow_index : felt
    member deposit : Uint256
end

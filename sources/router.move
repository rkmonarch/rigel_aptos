module rigel::router {
    
    struct UserDetails has key, store, drop {}

    struct PoolDetails has key, store, drop {}

    public fun whitelist_adapter() {}

    public fun delist_adapter() {}

    public fun open_position() {}

    public fun close_position() {}
}
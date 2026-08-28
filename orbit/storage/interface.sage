# orbit/storage/interface.sage — storage backend interface (§28)
# Orbit Blockchain | Protocol v1 | Status: skeleton


# Consensus code depends on THIS interface, never on JSON directly.
class Store:
    proc put_block(self, block): raise "skeleton"
    proc get_block(self, h): raise "skeleton"
    proc get_block_by_height(self, height): raise "skeleton"
    proc put_state(self, key, value): raise "skeleton"
    proc get_state(self, key): raise "skeleton"
    proc commit(self): raise "skeleton"

import sys

# Cache Configuration (Matching the RTL)
NUM_CORES = 4
CACHE_DEPTH = 64        # Number of sets
WAYS = 2                # 2-Way Set Associative
LINE_SIZE = 16          # 16 Bytes per line (128 bits)

# MESI States
INVALID = 'I'
SHARED = 'S'
EXCLUSIVE = 'E'
MODIFIED = 'M'

# Bus Operations
BUS_RD = "BusRd"
BUS_RDX = "BusRdX"
BUS_UPGR = "BusUpgr"
BUS_WB = "BusWB"

class CacheLine:
    def __init__(self):
        self.state = INVALID
        self.tag = None
        self.data = 0

class CacheSet:
    def __init__(self):
        self.lines = [CacheLine() for _ in range(WAYS)]
        self.lru_bit = 0 # 0 means Way 0 is LRU, 1 means Way 1 is LRU

    def update_lru(self, accessed_way):
        # If we accessed way 0, way 1 becomes the LRU. If accessed way 1, way 0 becomes LRU.
        self.lru_bit = 1 - accessed_way

    def get_lru_way(self):
        return self.lru_bit

class Cache:
    def __init__(self, core_id, system):
        self.core_id = core_id
        self.system = system
        self.sets = [CacheSet() for _ in range(CACHE_DEPTH)]

        # --- Statistics Tracking ---
        self.read_hits = 0
        self.read_misses = 0
        self.write_hits = 0
        self.write_misses = 0

    def _parse_addr(self, addr):
        block_addr = addr // LINE_SIZE
        index = block_addr % CACHE_DEPTH
        tag = block_addr // CACHE_DEPTH
        return tag, index

    def _find_line(self, tag, index):
        for way in range(WAYS):
            if self.sets[index].lines[way].state != INVALID and self.sets[index].lines[way].tag == tag:
                return way, self.sets[index].lines[way]
        return None, None

    def read(self, addr):
        tag, index = self._parse_addr(addr)
        way, line = self._find_line(tag, index)

        print(f"[CORE {self.core_id}] PrRd (Read) at Addr: {hex(addr)}")

        if line is not None:
            # READ HIT
            self.read_hits += 1
            print(f"  -> Cache HIT in Way {way} (State: {line.state})")
            self.sets[index].update_lru(way)
            return line.data
        else:
            # READ MISS
            self.read_misses += 1
            print("  -> Cache MISS")
            victim_way, victim_line = self._evict_if_needed(index)
            
            # Broadcast BusRd
            shared, fetched_data = self.system.bus_transaction(self.core_id, BUS_RD, addr)
            
            # Allocate new line
            victim_line.state = SHARED if shared else EXCLUSIVE
            victim_line.tag = tag
            victim_line.data = fetched_data
            self.sets[index].update_lru(victim_way)
            
            print(f"  -> Line Allocated in Way {victim_way}. New State: {victim_line.state}")
            return victim_line.data

    def write(self, addr, data):
        tag, index = self._parse_addr(addr)
        way, line = self._find_line(tag, index)

        print(f"[CORE {self.core_id}] PrWr (Write) at Addr: {hex(addr)} with Data: {hex(data)}")

        if line is not None:
            # WRITE HIT
            self.write_hits += 1
            print(f"  -> Cache HIT in Way {way} (State: {line.state})")
            if line.state == SHARED:
                # Write Upgrade
                self.system.bus_transaction(self.core_id, BUS_UPGR, addr)
            
            line.state = MODIFIED
            line.data = data
            self.sets[index].update_lru(way)
            print(f"  -> State updated to {MODIFIED}")
        else:
            # WRITE MISS
            self.write_misses += 1
            print("  -> Cache MISS")
            victim_way, victim_line = self._evict_if_needed(index)
            
            # Broadcast BusRdX
            _, _ = self.system.bus_transaction(self.core_id, BUS_RDX, addr)
            
            # Allocate and Write
            victim_line.state = MODIFIED
            victim_line.tag = tag
            victim_line.data = data
            self.sets[index].update_lru(victim_way)
            print(f"  -> Line Allocated in Way {victim_way}. New State: {MODIFIED}")

    def _evict_if_needed(self, index):
        c_set = self.sets[index]
        
        # 1. Prefer Invalid Lines
        for way in range(WAYS):
            if c_set.lines[way].state == INVALID:
                return way, c_set.lines[way]
        
        # 2. Use LRU Policy
        lru_way = c_set.get_lru_way()
        victim_line = c_set.lines[lru_way]
        print(f"  -> Evicting Way {lru_way} (Tag: {victim_line.tag}, State: {victim_line.state})")
        
        # Writeback if dirty
        if victim_line.state == MODIFIED:
            evict_addr = (victim_line.tag * CACHE_DEPTH + index) * LINE_SIZE
            self.system.bus_transaction(self.core_id, BUS_WB, evict_addr, victim_line.data)
            
        return lru_way, victim_line

    def snoop(self, bus_op, addr):
        tag, index = self._parse_addr(addr)
        way, line = self._find_line(tag, index)

        if line is None:
            return False, None # Not in this cache
            
        shared_asserted = False
        flushed_data = None

        if bus_op == BUS_RD:
            if line.state == MODIFIED:
                print(f"    [SNOOP Core {self.core_id}] Flushed dirty data to memory! Downgrading M -> S")
                flushed_data = line.data
                line.state = SHARED
                shared_asserted = True
            elif line.state == EXCLUSIVE:
                print(f"    [SNOOP Core {self.core_id}] Downgrading E -> S")
                line.state = SHARED
                shared_asserted = True
            elif line.state == SHARED:
                shared_asserted = True

        elif bus_op == BUS_RDX:
            if line.state == MODIFIED:
                print(f"    [SNOOP Core {self.core_id}] Flushed dirty data! Invalidating M -> I")
                flushed_data = line.data
            else:
                print(f"    [SNOOP Core {self.core_id}] Invalidating {line.state} -> I")
            line.state = INVALID

        elif bus_op == BUS_UPGR:
            if line.state == SHARED:
                print(f"    [SNOOP Core {self.core_id}] Invalidating S -> I")
                line.state = INVALID

        return shared_asserted, flushed_data

class System:
    def __init__(self):
        self.main_memory = {}
        self.caches = [Cache(i, self) for i in range(NUM_CORES)]

    def bus_transaction(self, master_id, bus_op, addr, wb_data=None):
        print(f"  [BUS] Master Core {master_id} broadcasts {bus_op} for Addr {hex(addr)}")
        
        if bus_op == BUS_WB:
            self.main_memory[addr] = wb_data
            print(f"    [MEM] Wrote back {hex(wb_data)} to {hex(addr)}")
            return False, None

        shared = False
        flushed_data = None

        # All other caches snoop the bus
        for core_id, cache in enumerate(self.caches):
            if core_id != master_id:
                s, d = cache.snoop(bus_op, addr)
                if s: shared = True
                if d is not None: flushed_data = d

        # Memory intervention / fetching
        if flushed_data is not None:
            # Another cache had dirty data and flushed it. Memory absorbs it.
            self.main_memory[addr] = flushed_data
            data_to_return = flushed_data
        else:
            # Standard memory fetch
            if addr not in self.main_memory:
                self.main_memory[addr] = 0 # Default initialize memory
            data_to_return = self.main_memory[addr]

        return shared, data_to_return

    def print_stats(self):
        print("\n==================================================")
        print(" PYTHON CACHE PERFORMANCE STATISTICS (HIT RATE)")
        print("==================================================")
        total_sys_hits = 0
        total_sys_misses = 0
        
        for core_id, cache in enumerate(self.caches):
            hits = cache.read_hits + cache.write_hits
            misses = cache.read_misses + cache.write_misses
            accesses = hits + misses
            
            total_sys_hits += hits
            total_sys_misses += misses
            
            hit_rate = (hits / accesses * 100) if accesses > 0 else 0.0
            
            print(f" CORE {core_id}:")
            print(f"   Reads  : {cache.read_hits} Hits, {cache.read_misses} Misses")
            print(f"   Writes : {cache.write_hits} Hits, {cache.write_misses} Misses")
            print(f"   Hit Rate: {hit_rate:.2f}% ({hits}/{accesses} Accesses)")
            print("-" * 50)
            
        sys_accesses = total_sys_hits + total_sys_misses
        sys_hit_rate = (total_sys_hits / sys_accesses * 100) if sys_accesses > 0 else 0.0
        print(f" SYSTEM TOTAL HIT RATE: {sys_hit_rate:.2f}% ({total_sys_hits}/{sys_accesses} Accesses)")
        print("==================================================\n")

if __name__ == "__main__":
    import random
    
    print("==================================================")
    print(" PYTHON MESI 2-WAY LRU GOLDEN REFERENCE MODEL")
    print("==================================================")
    
    sys = System()

    # Generate a deterministic trace file for Verilog to consume
    NUM_TRANSACTIONS = 1000
    random.seed(42) # Fixed seed ensures the same trace every time
    
    with open("cpu_trace.txt", "w") as f:
        for _ in range(NUM_TRANSACTIONS):
            core_id = random.randint(0, 3)
            rw = random.randint(0, 1)
            block_addr = random.randint(0, 15)
            addr = block_addr * LINE_SIZE
            data = random.randint(1, 9999) if rw else 0
            
            # Format the instruction as a single 167-bit hex string for Verilog
            # Core (2 bits), RW (1 bit), Addr (32 bits), Data (128 bits), Valid (4 bits)
            # Since Python handles arbitrarily large integers, we can just bit-shift:
            instruction = (core_id << 165) | (rw << 164) | (addr << 132) | (data << 4) | 0xF
            
            # Write it as a padded hex string (42 hex characters for 167 bits)
            f.write(f"{instruction:042X}\n")
            
            # Execute in Golden Model
            if rw == 0:
                sys.caches[core_id].read(addr)
            else:
                sys.caches[core_id].write(addr, data)
                
    # Generate and print the Hit Rate report
    sys.print_stats()
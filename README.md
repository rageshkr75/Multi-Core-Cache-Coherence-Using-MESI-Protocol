# Multi-Core L1 Cache Subsystem with MESI Coherence

## Overview
This project is a synthesizable RTL implementation of a 4-core, 2-way set-associative L1 cache subsystem featuring strict MESI cache coherence, hardware LRU replacement, and a shared-bus interconnect. It was verified using a custom Python golden model and Constrained-Random Verification (CRV) to ensure zero coherence violations under heavy multi-core traffic.

## Architectural Features
* **4-Core L1 Cache:** 2-way set-associative, 16-byte cache lines, write-back policy.
* **MESI Protocol:** Decentralized bus-snooping logic actively monitoring shared bus traffic to enforce Modified, Exclusive, Shared, and Invalid state transitions.
* **Dual-Ported State Arrays:** True dual-ported tag and MESI arrays physically decouple the CPU pipeline from snoop interventions, preventing structural hazards during concurrent cache-to-cache flushes.
* **Bus Arbiter:** Masked round-robin arbitration for fair bus access across all 4 core caches.

## Verification Methodology
Hardware coherence was verified against a Python Golden Model. The verification environment utilizes:
* **Constrained-Random Traffic:** A randomized 1,000-transaction memory trace tailored to force pathological sharing, bus upgrades, and dirty eviction races.
* **Cycle-Accurate Assertion Monitors:** Custom Verilog protocol police continuously monitor the state arrays of all 4 cores simultaneously.
* **Results:** Zero data corruptions and zero MESI protocol violations detected across 50,000+ simulation cycles while sustaining a 39% hit rate under extreme contention.

## Repository Structure
* `/rtl`: Contains all Verilog source code for the cache controllers, memory arrays, FSMs, and the bus arbiter.
* `/tb`: Contains the top-level testbench (`tb_mesi.v`) with embedded assertion monitors.
* `/verification`: Contains the Python Golden Model (`golden.py`) used to generate the baseline truth and memory traces.


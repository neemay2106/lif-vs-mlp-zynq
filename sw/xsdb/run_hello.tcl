# run_hello.tcl - load and run hello_world on the ZedBoard over JTAG with XSDB
#
# Usage (Linux, board in JTAG boot mode, Vitis debug sessions stopped):
#     xsdb run_hello.tcl
#
# Same sequence the Vitis "Run" button performs:
#   reset system -> program PL -> ps7_init -> ps7_post_config -> download ELF -> run

# ---- paths: edit these to match your workspace ----
set WS     $::env(HOME)/vits
set BIT    $WS/hello_world/_ide/bitstream/design_1_wrapper.bit
set PSINIT $WS/hello_world/_ide/psinit/ps7_init.tcl
set ELF    $WS/hello_world/build/hello_world.elf

foreach f [list $BIT $PSINIT $ELF] {
    if {![file exists $f]} {
        puts "ERROR: file not found: $f"
        exit 1
    }
}

# ---- connect to hw_server (starts a local one if none is running) ----
connect

# ---- reset the whole Zynq (PS + PL) ----
targets -set -nocase -filter {name =~ "APU*"}
rst -system
after 1000

# ---- program the PL ----
targets -set -nocase -filter {name =~ "xc7z020*"}
fpga -file $BIT

# ---- init PS: clocks, MIO, DDR, then enable PS-PL level shifters ----
targets -set -nocase -filter {name =~ "APU*"}
source $PSINIT
ps7_init
ps7_post_config

# ---- download and run on core 0 ----
targets -set -nocase -filter {name =~ "*A9*#0"}
dow $ELF
#con

puts "hello_world running - check the serial terminal"

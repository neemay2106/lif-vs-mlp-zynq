# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "B1_INIT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "B2_INIT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "B3_INIT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "W1_INIT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "W2_INIT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "W3_INIT" -parent ${Page_0}


}

proc update_PARAM_VALUE.B1_INIT { PARAM_VALUE.B1_INIT } {
	# Procedure called to update B1_INIT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.B1_INIT { PARAM_VALUE.B1_INIT } {
	# Procedure called to validate B1_INIT
	return true
}

proc update_PARAM_VALUE.B2_INIT { PARAM_VALUE.B2_INIT } {
	# Procedure called to update B2_INIT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.B2_INIT { PARAM_VALUE.B2_INIT } {
	# Procedure called to validate B2_INIT
	return true
}

proc update_PARAM_VALUE.B3_INIT { PARAM_VALUE.B3_INIT } {
	# Procedure called to update B3_INIT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.B3_INIT { PARAM_VALUE.B3_INIT } {
	# Procedure called to validate B3_INIT
	return true
}

proc update_PARAM_VALUE.W1_INIT { PARAM_VALUE.W1_INIT } {
	# Procedure called to update W1_INIT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.W1_INIT { PARAM_VALUE.W1_INIT } {
	# Procedure called to validate W1_INIT
	return true
}

proc update_PARAM_VALUE.W2_INIT { PARAM_VALUE.W2_INIT } {
	# Procedure called to update W2_INIT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.W2_INIT { PARAM_VALUE.W2_INIT } {
	# Procedure called to validate W2_INIT
	return true
}

proc update_PARAM_VALUE.W3_INIT { PARAM_VALUE.W3_INIT } {
	# Procedure called to update W3_INIT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.W3_INIT { PARAM_VALUE.W3_INIT } {
	# Procedure called to validate W3_INIT
	return true
}


proc update_MODELPARAM_VALUE.W1_INIT { MODELPARAM_VALUE.W1_INIT PARAM_VALUE.W1_INIT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.W1_INIT}] ${MODELPARAM_VALUE.W1_INIT}
}

proc update_MODELPARAM_VALUE.B1_INIT { MODELPARAM_VALUE.B1_INIT PARAM_VALUE.B1_INIT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.B1_INIT}] ${MODELPARAM_VALUE.B1_INIT}
}

proc update_MODELPARAM_VALUE.W2_INIT { MODELPARAM_VALUE.W2_INIT PARAM_VALUE.W2_INIT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.W2_INIT}] ${MODELPARAM_VALUE.W2_INIT}
}

proc update_MODELPARAM_VALUE.B2_INIT { MODELPARAM_VALUE.B2_INIT PARAM_VALUE.B2_INIT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.B2_INIT}] ${MODELPARAM_VALUE.B2_INIT}
}

proc update_MODELPARAM_VALUE.W3_INIT { MODELPARAM_VALUE.W3_INIT PARAM_VALUE.W3_INIT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.W3_INIT}] ${MODELPARAM_VALUE.W3_INIT}
}

proc update_MODELPARAM_VALUE.B3_INIT { MODELPARAM_VALUE.B3_INIT PARAM_VALUE.B3_INIT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.B3_INIT}] ${MODELPARAM_VALUE.B3_INIT}
}


#////////////////////////////////////////////////////////////////////////////////
#  project：dma_test                                                           //
#                                                                              //
#  Author: JunFN                                                               //
#          853808728@qq.com                                                    //
#          ALINX(shanghai) Technology Co.,Ltd                                  //
#          黑金                                                                //
#     WEB: http://www.alinx.cn/                                                //
#                                                                              //
#////////////////////////////////////////////////////////////////////////////////
#                                                                              //
# Copyright (c) 2017,ALINX(shanghai) Technology Co.,Ltd                        //
#                    All rights reserved                                       //
#                                                                              //
# This source file may be used and distributed without restriction provided    //
# that this copyright statement is not removed from the file and that any      //
# derivative work contains the original copyright notice and the associated    //
# disclaimer.                                                                  //
#                                                                              // 
#////////////////////////////////////////////////////////////////////////////////

#================================================================================
#  Revision History:
#  Date          By            Revision    Change Description
# --------------------------------------------------------------------------------
#  2023/8/22                   1.0          Original
#=================================================================================
# Extracted DDR parameters from ALINX AX7020_2023.1 commit
# fcf1e4a239b0f47e8ee95dfde7c2eedc5685c327, 15_dma_loopback/ps_config.tcl
proc configure_ax7020_ddr {ps} {
set_property -dict [list \
  CONFIG.PCW_UIPARAM_DDR_ADV_ENABLE {0} \
  CONFIG.PCW_UIPARAM_DDR_AL {0} \
  CONFIG.PCW_UIPARAM_DDR_BL {8} \
  CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.25} \
  CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.25} \
  CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.25} \
  CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.25} \
  CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_0_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PACKAGE_LENGTH {80.4535} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_1_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PACKAGE_LENGTH {80.4535} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_2_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PACKAGE_LENGTH {80.4535} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_3_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PACKAGE_LENGTH {80.4535} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_CLOCK_STOP_EN {0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_0_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_0_PACKAGE_LENGTH {105.056} \
  CONFIG.PCW_UIPARAM_DDR_DQS_0_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_DQS_1_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_1_PACKAGE_LENGTH {66.904} \
  CONFIG.PCW_UIPARAM_DDR_DQS_1_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_DQS_2_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_2_PACKAGE_LENGTH {89.1715} \
  CONFIG.PCW_UIPARAM_DDR_DQS_2_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_DQS_3_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_3_PACKAGE_LENGTH {113.63} \
  CONFIG.PCW_UIPARAM_DDR_DQS_3_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} \
  CONFIG.PCW_UIPARAM_DDR_DQ_0_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_DQ_0_PACKAGE_LENGTH {98.503} \
  CONFIG.PCW_UIPARAM_DDR_DQ_0_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_DQ_1_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_DQ_1_PACKAGE_LENGTH {68.5855} \
  CONFIG.PCW_UIPARAM_DDR_DQ_1_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_DQ_2_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_DQ_2_PACKAGE_LENGTH {90.295} \
  CONFIG.PCW_UIPARAM_DDR_DQ_2_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_DQ_3_LENGTH_MM {0} \
  CONFIG.PCW_UIPARAM_DDR_DQ_3_PACKAGE_LENGTH {103.977} \
  CONFIG.PCW_UIPARAM_DDR_DQ_3_PROPOGATION_DELAY {160} \
  CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
  CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
  CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP {Normal (0-85)} \
  CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3} \
  CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J256M16 RE-125} \
  CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} \
  CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
  CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
  CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {0} \
] $ps
}

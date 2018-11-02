xCORE-200 explorer - Accelerometer
==================================

.. version:: 1.0.0

Summary
-------

This application note show how to the accelerometer on an xCORE-200 explorer
development kit. The kit itself has a Freescale FXOS8700CQ 6-Axis sensor with
interated linear accelerometer and magnetometer. 

The example uses the XMOS I2C library to demonstrate how I2C devices
can be accessed in an easy and efficient manner. It shows how to access the 
registers of an I2C device connected to the GPIO of an XMOS multicore micro controller.

The code in the example builds a simple application which configures the FXOS8700CQ accelerometer and
reports x,y and z acceleration values to the user. Data is output to the development console
using xSCOPE and the accelerometer state is also reported via the RGB LED on the
xCORE-200 explorer board.

Required tools and libraries
............................

* xTIMEcomposer Tools - Version 14.0 
* XMOS I2C library - Version 2.0.0

Required hardware
.................

This application note is designed to run on any XMOS multicore microcontroller.

The example code provided with the application has been implemented and tested
on the xCORE-200 explorer kit. The dependancy on this board is due to the FXOS8700CQ
accelerometer being connected to the specific GPIO ports defined in the example. The
same device could easily be added to another XMOS development platform.

Prerequisites
.............

  - This document assumes familiarity with the XMOS xCORE architecture, the XMOS GPIO library, 
    the XMOS tool chain and the xC language. Documentation related to these aspects which are 
    not specific to this application note are linked to in the references appendix.

  - For descriptions of XMOS related terms found in this document please see the XMOS Glossary [#]_.

  - For the information relating to the I2C library, please see the document XMOS GPIO Library [#]_.

  - For the Freescale FXOS8700CQ device see the published datasheet [#]_.

  .. [#] http://www.xmos.com/published/glossary

  .. [#] http://www.xmos.com/published/xmos-gpio-lib

  .. [#] http://www.freescale.com/webapp/sps/site/prod_summary.jsp?code=FXOS8700CQ


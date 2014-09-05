# kitchen-dsc
A Test Kitchen Provisioner for PowerShell DSC

The provider works by passing the DSC repository based on attributes in .kitchen.yml & calling SendConfigurationApply.

This provider has been tested against the Ubuntu 1204 and Centos 6.5 boxes running in vagrant/virtualbox.

## Requirements
You'll need a driver box with WMF4 or greater. 

## Installation & Setup
You'll need the test-kitchen & kitchen-dsc gems installed in your system, along with kitchen-vagrant or some ther suitable driver for test-kitchen. 

Please see the Provisioner Options (https://github.com/smurawski/kitchen-dsc/blob/master/provisioner_options.md).
#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
#
# Licensed under the Apache 2 License.
# See LICENSE for more details

module Kitchen
  # Namespace for the kitchen-dsc plugin's own metadata.
  #
  # The provisioner itself lives in {Kitchen::Provisioner::Dsc}; this module
  # exists so the gemspec can read the version without loading Test Kitchen.
  module Dsc
    # The released version of the kitchen-dsc gem.
    #
    # Kept in sync with the gemspec by release-please; changing it by hand is
    # only appropriate as part of a release commit.
    #
    # @return [String] a frozen dotted version number
    VERSION = "0.13.1".freeze
  end
end

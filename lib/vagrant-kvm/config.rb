module VagrantPlugins
  module ProviderKvm
    class Config < Vagrant.plugin("2", :config)
      # An array of customizations to make on the VM prior to booting it.
      #
      # @return [Array]
      attr_accessor :customize

      # Amount of Memory in MiBs
      #
      # @return [String]
      attr_accessor :memory

      # Number of CPU cores.
      #
      # @return [String]
      attr_accessor :cpus

      # This should be architecture of VM
      #
      # @return [String]
      attr_accessor :cpu_model

      # If set to `true`, then KVM/Qemu will be launched with a VNC console.
      #
      # @return [Boolean]
      attr_accessor :gui

      # This should be set to the name of the VM
      #
      # @return [String]
      attr_accessor :name

      # The defined network adapters.
      #
      # @return [Hash]
      attr_reader :network_adapters

      # The VM image format
      #
      # @return [String]
      attr_accessor :image_type

      # path of qemu binary
      #
      # @return [String]
      attr_accessor :qemu_bin

      def initialize
        @name             = UNSET_VALUE
        @gui              = UNSET_VALUE
        @image_type       = UNSET_VALUE
        @qemu_bin         = UNSET_VALUE
        @cpu_model       = UNSET_VALUE
      end

      # This is the hook that is called to finalize the object before it
      # is put into use.
      def finalize!
        # The default name is just nothing, and we default it
        @name = nil if @name == UNSET_VALUE
        # Default is to not show a GUI
        @gui = false if @gui == UNSET_VALUE
        # Default image type is a sparsed raw
        @image_type = 'qcow2' if @image_type == UNSET_VALUE
        # Search qemu binary with the default behavior
        @qemu_bin = nil if @qemu_bin == UNSET_VALUE
      end
    end
  end
end

require "log4r"

module VagrantPlugins
  module ProviderKvm
    module Action
      # This middleware class configures networking
      class Network

        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant::plugins::kvm::network")
          @app    = app
        end

        def call(env)
          # TODO: Validate network configuration prior to anything below
          @env = env
          options = {}
          env[:machine].config.vm.networks.find do |type, network_options|
              if type == :public_network
                if network_options[:bridge]
                  options[:type] = :bridge
                  options[:source] = network_options[:bridge]
                elsif network_options[:public_network]
                  options[:type] = :network
                  options[:source] = network_options[:public_network]
                else
                  options[:type] = :default
                  options[:source] = :default
                end
              end
          end

          env[:ui].info I18n.t("vagrant.actions.vm.network.preparing")
          env[:machine].provider.driver.create_network(options)

          @app.call(env)
        end
      end
    end
  end
end

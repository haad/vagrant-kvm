module VagrantPlugins
  module ProviderKvm
    module Action
      class SetMemory
        def initialize(app, env)
          @logger = Log4r::Logger.new("vagrant::action::vm::setvcpu")
          @app = app
        end

        def call(env)
          memory = env[:machine].provider_config.memory

          if !memory
            memory = nil
          end

          # @todo Check available amount of memory

          @logger.info("Setting number of memory to: #{memory}")
          env[:machine].provider.driver.set_memory(memory)

          @app.call(env)
        end

      end
    end
  end
end

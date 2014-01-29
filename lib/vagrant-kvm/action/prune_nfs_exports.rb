module VagrantPlugins
  module ProviderKvm
    module Action
      class PruneNFSExports
        def initialize(app, env)
          @app = app
        end

        def call(env)
          if env[:host]
            # make sure we don't prune running vms
            conn = Util::LibvirtHelper.connect
            domains = conn.list_domains
            domains = domains.map do |id|
              conn.lookup_domain_by_id id
            end
            Util::LibvirtHelper.disconnect(conn)

            env[:host].nfs_prune domains.map(&:uuid)
          end

          @app.call(env)
        end
      end
    end
  end
end

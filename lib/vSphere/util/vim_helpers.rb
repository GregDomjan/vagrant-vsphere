require 'rbvmomi'

module VagrantPlugins
  module VSphere
    module Util
      module VimHelpers
        def get_datacenter(connection, machine)
          connection.serviceInstance.find_datacenter(machine.provider_config.data_center_name) or fail Errors::VSphereError, :missing_datacenter
        end

        def get_vm_by_uuid(connection, machine)
          get_datacenter(connection, machine).vmFolder.findByUuid machine.id
        end

        def get_resource_pool(computeResource, machine)
          rp = computeResource.resourcePool
          if !(machine.provider_config.resource_pool_name.nil?)
            rp = computeResource.resourcePool.find(machine.provider_config.resource_pool_name) or  fail Errors::VSphereError, :missing_resource_pool
          end
          rp
        end

        def get_compute_resource(datacenter, machine)
          cr = find_clustercompute_or_compute_resource(datacenter, machine.provider_config.compute_resource_name) or fail Errors::VSphereError, :missing_compute_resource
          cr
        end

# Is it better to check for either type or have the type configured?
        def find_clustercompute_or_compute_resource(datacenter, path)
#          puts "looking for compute resource `" + path + "`"
          if path.is_a? String
            es = path.split('/').reject(&:empty?)
          elsif path.is_a? Enumerable
            es = path
          else
            fail "unexpected path class #{path.class}"
          end
          return datacenter.hostFolder if es.empty?
          final = es.pop
          
          p = es.inject(datacenter.hostFolder) do |f,e|
#            puts "looking for `" + e + "` within " + f.to_json
            f.find(e, RbVmomi::VIM::Folder) || return
          end

#          puts "last folder found " + p.to_json
          begin
            if x = p.find(final, RbVmomi::VIM::ComputeResource)
#              puts "Compute " + x.to_json
              x
            elsif x = p.find(final, RbVmomi::VIM::ClusterComputeResource)
#              puts "Cluster Compute " + x.to_json
              x
            else
              nil
            end
          rescue Exception => e
            x = p.childEntity.find { |x| x.name == final }
            if x.is_a? RbVmomi::VIM::ClusterComputeResource or x.is_a? RbVmomi::VIM::ComputeResource
              x
            else
              puts "ex unknonw type " + x.to_json
              nil
            end
          end

        end

        def get_customization_spec_info_by_name(connection, machine)
          name = machine.provider_config.customization_spec_name
          return if name.nil? || name.empty?

          manager = connection.serviceContent.customizationSpecManager or fail Errors::VSphereError, :null_configuration_spec_manager if manager.nil?
          spec = manager.GetCustomizationSpec(:name => name) or fail Errors::VSphereError, :missing_configuration_spec if spec.nil?
        end

        def get_datastore(datacenter, machine)
          name = machine.provider_config.data_store_name
          podname = machine.provider_config.data_store_name
          return if ( name.nil? || name.empty? ) && ( podname.nil? || podname.empty? )
		  
# find_datastore uses datastore that only lists Datastore and not StoragePod
          datacenter.find_datastore name or datacenter.datastoreFolder.find podname or fail Errors::VSphereError, :missing_datastore
        end

        def get_network_by_name(dc, name)
          dc.network.find { |f| f.name == name } or fail Errors::VSphereError, :missing_vlan
        end

        def ClusterClone( connection, dscluster, template, folder, name, spec )
          storageMgr = connection.serviceContent.storageResourceManager
          podSpec = RbVmomi::VIM.StorageDrsPodSelectionSpec(:storagePod => dscluster)
# May want to add option on type? 
          storageSpec = RbVmomi::VIM.StoragePlacementSpec(:type => 'clone', :cloneName => name, :folder => folder, :podSelectionSpec => podSpec, :vm => template, :cloneSpec => spec)
          begin
            result = storageMgr.RecommendDatastores(:storageSpec => storageSpec)

            #retrieve SDRS recommendation
            key = result.recommendations[0].key ||= ''
            if key == ''
              raise Errors::VSphereError, :missing_datastore
#              abort("\n\n>>> ERROR: NO DATASTORE RECOMMENDATION WAS RETURNED IN #{environment} FOR #{@datastore_cluster}\n\n")
            end

#            if async
#              storageMgr.ApplyStorageDrsRecommendation_Task(:key => [key])
#            else
              applySRresult = storageMgr.ApplyStorageDrsRecommendation_Task(:key => [key]).wait_for_completion
              applySRresult.vm
#			  puts foo.inspect
#              name
#            end
          rescue Exception => e
            puts e
            raise e
#                 abort("no recommendation returned")
          end

        end

      end
    end
  end
end

module DuctExtension
  module Services
    module NetworkRebuildService
      DICTIONARY = "DuctExtension"

      def self.rebuild(model)
        network = Model::Network.new

        groups = collect_groups(model.entities)

        groups.each do |group|
          piece = PieceMetadataService.load_piece(group)
          next unless piece

          network.add_piece(piece)
        end

        reconnect_touching_ports(network)

        ::DuctExtension.instance_variable_get(:@model_networks)[model.guid] = network

        network
      rescue => error
        puts "NetworkRebuildService.rebuild failed: #{error.message}"
        puts error.backtrace.join("\n")

        ::DuctExtension.network_for_model(model)
      end

      def self.collect_groups(entities, results = [])
        entities.grep(Sketchup::Group).each do |group|
          next unless group.valid?

          results << group

          collect_groups(group.entities, results)
        end

        entities.grep(Sketchup::ComponentInstance).each do |instance|
          next unless instance.valid?

          # Avoid descending into arbitrary component definitions. Our duct
          # geometry is stored as groups, not component instances.
        end

        results
      rescue => error
        puts "NetworkRebuildService.collect_groups failed: #{error.message}"
        results
      end

      def self.reconnect_touching_ports(network)
        ports = network.ports

        ports.each_with_index do |port_a, index|
          ((index + 1)...ports.length).each do |other_index|
            port_b = ports[other_index]

            next unless port_a && port_b
            next if port_a.piece == port_b.piece
            next if network.connected?(port_a, port_b)

            distance = port_a.point.distance(port_b.point)

            next if distance > Model::Network::CONNECTION_DISTANCE * 4.0

            network.connect_ports(port_a, port_b)
          end
        end

        network.rebuild_index! if network.respond_to?(:rebuild_index!)
      end
    end
  end
end

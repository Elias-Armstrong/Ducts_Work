# ===== Consolidated from: services/piece_metadata_service.rb =====
require 'json'

module DuctExtension
  module Services
    module PieceMetadataService
      DICTIONARY = "DuctExtension"

      def self.save_piece(piece)
        return false unless piece
        return false unless piece.group && piece.group.valid?

        group = piece.group

        group.set_attribute(DICTIONARY, "is_duct_piece", true)
        group.set_attribute(DICTIONARY, "type", piece.type.to_s)

        ports_data = Array(piece.ports).map do |port|
          port_to_h(port)
        end

        # JSON is safer than relying on SketchUp attribute support for nested
        # arrays/hashes across versions.
        group.set_attribute(DICTIONARY, "ports_json", JSON.generate(ports_data))

        true
      rescue => error
        puts "PieceMetadataService.save_piece failed: #{error.message}"
        false
      end

      def self.load_piece(group)
        return nil unless group && group.valid?

        is_piece = group.get_attribute(DICTIONARY, "is_duct_piece")
        type_text = group.get_attribute(DICTIONARY, "type")

        return nil unless is_piece
        return nil unless type_text

        ports = load_ports(group)
        return nil if ports.empty?

        piece = Model::DuctPiece.new(
          type: type_text.to_sym,
          group: group,
          ports: ports
        )

        piece.ports.each { |port| port.piece = piece }

        piece
      rescue => error
        puts "PieceMetadataService.load_piece failed: #{error.message}"
        nil
      end

      def self.load_ports(group)
        json = group.get_attribute(DICTIONARY, "ports_json")

        if json && !json.to_s.empty?
          data = JSON.parse(json)
          return Array(data).map { |item| Model::Port.from_h(item) }.compact
        end

        # Legacy fallback in case older files used direct array/hash attributes.
        legacy = group.get_attribute(DICTIONARY, "ports")
        return [] unless legacy

        Array(legacy).map { |item| Model::Port.from_h(item) }.compact
      rescue => error
        puts "PieceMetadataService.load_ports failed: #{error.message}"
        []
      end

      def self.port_to_h(port)
        {
          "point" => point_array(port.point),
          "vector" => vector_array(port.vector),
          "diameter" => port.diameter.to_f,
          "shape" => port.shape.to_s,
          "width" => port.width.to_f,
          "height" => port.height.to_f,
          "width_axis" => port.width_axis ? vector_array(port.width_axis) : nil,
          "height_axis" => port.height_axis ? vector_array(port.height_axis) : nil
        }
      end

      def self.point_array(point)
        [point.x.to_f, point.y.to_f, point.z.to_f]
      end

      def self.vector_array(vector)
        [vector.x.to_f, vector.y.to_f, vector.z.to_f]
      end

      def self.clear_group_metadata(group)
        return unless group && group.valid?

        group.delete_attribute(DICTIONARY)
      rescue => error
        puts "PieceMetadataService.clear_group_metadata failed: #{error.message}"
      end
    end
  end
end

# ===== Consolidated from: services/network_rebuild_service.rb =====
module DuctExtension
  module Services
    module NetworkRebuildService
      DICTIONARY = "DuctExtension"

      def self.rebuild(model, target_network: nil)
        rebuilt = Model::Network.new

        collect_groups(model.entities).each do |group|
          piece = PieceMetadataService.load_piece(group)
          rebuilt.add_piece(piece) if piece
        end

        reconnect_touching_ports(rebuilt)

        network = target_network || rebuilt
        network.replace_from!(rebuilt) if target_network

        ::DuctExtension.instance_variable_get(:@model_networks)[model.guid] = network
        network
      rescue => error
        puts "NetworkRebuildService.rebuild failed: #{error.message}"
        puts error.backtrace.join("\n")

        target_network || ::DuctExtension.network_for_model(model)
      end

      def self.collect_groups(entities, results = [])
        entities.grep(Sketchup::Group).each do |group|
          next unless group.valid?

          results << group
          collect_groups(group.entities, results)
        end

        # Duct geometry is stored as groups, not arbitrary component instances.
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
            next if port_a.point.distance(port_b.point) > Model::Network::CONNECTION_DISTANCE * 4.0

            network.connect_ports(port_a, port_b)
          end
        end

        network.rebuild_index! if network.respond_to?(:rebuild_index!)
      end
    end
  end
end

# ===== Consolidated from: services/network_clear_service.rb =====
module DuctExtension
  module Services
    module NetworkClearService
      DICTIONARY = "DuctExtension"

      def self.clear_model_data(model, network = nil)
        return false unless model

        target_network = network || ::DuctExtension.network_for_model(model)

        ModelOperation.run(
          model: model,
          network: target_network,
          name: "Clear Duct Data",
          rebuild_on_failure: true
        ) do
          clear_entities(model.entities)
          target_network.clear
          true
        end
      rescue => error
        puts "NetworkClearService.clear_model_data failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def self.clear_entities(entities)
        entities.grep(Sketchup::Group).each do |group|
          next unless group.valid?

          if group.get_attribute(DICTIONARY, "is_duct_piece")
            group.delete_attribute(DICTIONARY)
          end

          clear_entities(group.entities)
        end
      rescue => error
        puts "NetworkClearService.clear_entities failed: #{error.message}"
      end

      private_class_method :clear_entities
    end
  end
end

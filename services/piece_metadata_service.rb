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

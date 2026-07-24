module DuctExtension
  module Services
    module NetworkValidator
      class ValidationError < StandardError
        attr_reader :errors

        def initialize(errors)
          @errors = Array(errors)
          super("Duct network validation failed:\n- #{@errors.join("\n- ")}")
        end
      end

      def self.validate(network, check_spatial_index: true, check_connection_distance: false)
        errors = []
        return ["network is nil"] unless network

        pieces = Array(network.pieces)
        ports = Array(network.ports)
        connections = Array(network.connections)

        duplicate_objects(pieces).each { |piece| errors << "piece is registered more than once: #{label_piece(piece)}" }
        duplicate_objects(ports).each { |port| errors << "port is registered more than once: #{label_port(port)}" }

        pieces.each do |piece|
          unless piece
            errors << "network contains a nil piece"
            next
          end

          unless piece.group && piece.group.valid?
            errors << "piece has an invalid SketchUp group: #{label_piece(piece)}"
          end

          Array(piece.ports).each do |port|
            unless port
              errors << "piece contains a nil port: #{label_piece(piece)}"
              next
            end

            errors << "piece port is missing from network.ports: #{label_port(port)}" unless ports.include?(port)
            errors << "port back-reference points to the wrong piece: #{label_port(port)}" unless port.piece.equal?(piece)
            validate_port(port, errors)
          end
        end

        ports.each do |port|
          next unless port

          errors << "network port has no piece: #{label_port(port)}" unless port.piece
          if port.piece && !pieces.include?(port.piece)
            errors << "network port references a piece not in network.pieces: #{label_port(port)}"
          end
          validate_port(port, errors)
        end

        seen_connections = {}
        connections.each do |connection|
          unless connection
            errors << "network contains a nil connection"
            next
          end

          port_a = connection.port_a
          port_b = connection.port_b

          errors << "connection has a missing endpoint" unless port_a && port_b
          next unless port_a && port_b

          errors << "connection references a port outside network.ports" unless ports.include?(port_a) && ports.include?(port_b)
          errors << "connection connects a port to itself: #{label_port(port_a)}" if port_a.equal?(port_b)

          key = [port_a.object_id, port_b.object_id].sort
          if seen_connections[key]
            errors << "duplicate connection between #{label_port(port_a)} and #{label_port(port_b)}"
          else
            seen_connections[key] = true
          end

          if check_connection_distance && port_a.point && port_b.point
            tolerance = Model::Network::CONNECTION_DISTANCE * 4.0
            distance = port_a.point.distance(port_b.point)
            errors << "connected ports are #{distance} apart (tolerance #{tolerance})" if distance > tolerance
          end
        end

        if check_spatial_index
          ports.each do |port|
            next unless port && port.point

            nearby = network.nearby_ports(port.point, 0.001)
            errors << "port is missing from spatial index: #{label_port(port)}" unless nearby.include?(port)
          rescue => error
            errors << "spatial index check failed for #{label_port(port)}: #{error.message}"
          end
        end

        errors.uniq
      rescue => error
        ["validator crashed: #{error.class}: #{error.message}"]
      end

      def self.validate!(network, **options)
        errors = validate(network, **options)
        raise ValidationError, errors unless errors.empty?

        true
      end

      def self.valid?(network, **options)
        validate(network, **options).empty?
      end

      def self.validate_port(port, errors)
        unless port.point
          errors << "port has no point: #{label_port(port)}"
        end

        vector = port.outward_vector if port.respond_to?(:outward_vector)
        if !vector || vector.length <= 0.000001
          errors << "port has a zero/invalid outward vector: #{label_port(port)}"
        end

        dimensions = Model::DuctDimensions.coerce(port.respond_to?(:dimensions) ? port.dimensions : port)
        if dimensions.round?
          errors << "round port has a non-positive diameter: #{label_port(port)}" unless dimensions.diameter > 0.0
        else
          errors << "rectangular port has a non-positive width: #{label_port(port)}" unless dimensions.width > 0.0
          errors << "rectangular port has a non-positive height: #{label_port(port)}" unless dimensions.height > 0.0
        end
      rescue => error
        errors << "port validation failed for #{label_port(port)}: #{error.message}"
      end

      def self.duplicate_objects(items)
        counts = Hash.new(0)
        Array(items).each { |item| counts[item.object_id] += 1 if item }
        Array(items).compact.select { |item| counts[item.object_id] > 1 }.uniq
      end
      private_class_method :duplicate_objects

      def self.label_piece(piece)
        return "nil" unless piece

        "#{piece.type rescue 'unknown'}##{piece.object_id}"
      end
      private_class_method :label_piece

      def self.label_port(port)
        return "nil" unless port

        piece_type = port.piece && port.piece.respond_to?(:type) ? port.piece.type : "unowned"
        "#{piece_type}-port##{port.object_id}"
      end
      private_class_method :label_port
    end
  end
end

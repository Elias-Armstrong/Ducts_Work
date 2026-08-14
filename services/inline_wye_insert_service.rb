module DuctExtension
  module Services
    class InlineWyeInsertService
      MIN_SEGMENT_LENGTH_FACTOR = 0.5

      def self.insert_wye_on_pipe(
        model:,
        network:,
        pipe_piece:,
        tap_point:,
        side_direction:,
        branch_dimensions: nil,
        forward_sign: 1.0
      )
        return nil unless model && network && pipe_piece
        return nil unless pipe_piece.type == :pipe && pipe_piece.ports.length == 2

        old_port_a = pipe_piece.ports[0]
        old_port_b = pipe_piece.ports[1]
        dimensions = Model::Port.dimensions_from_params({}, old_port_a)
        dims = Model::DuctDimensions.coerce(dimensions)

        unless Catalog::Manager.active?(model) && dims.round?
          ::UI.messagebox("Inline Wye Saddle is currently a Master Flow round-catalog operation.")
          return nil
        end

        product = Catalog::Manager.wye_saddle_product(dims, model)
        return Catalog::Manager.notify_unsupported(:wye_saddle, dims) unless product

        pipe_product = Catalog::Manager.pipe_product(dims, model)
        return Catalog::Manager.notify_unsupported(:pipe, dims) unless pipe_product

        point_a = old_port_a.point
        point_b = old_port_b.point
        main = point_a.vector_to(point_b)
        return nil if main.length <= 0.000001
        main.normalize!

        center = TeePlacementCalculator.project_point_to_segment(
          point: tap_point,
          line_start: point_a,
          line_end: point_b
        )
        return nil unless center

        side = Geometry::VectorMath.perpendicularized(side_direction, main)
        return nil unless side
        side.normalize!

        min_length = [dims.largest * MIN_SEGMENT_LENGTH_FACTOR, 1.0].max
        return nil if point_a.distance(center) < min_length
        return nil if point_b.distance(center) < min_length

        requested_branch_dimensions = Model::DuctDimensions.coerce(
          branch_dimensions || Model::DuctDimensions.round(diameter: product.branch_diameter.to_f),
          fallback: Model::DuctDimensions.round(diameter: product.branch_diameter.to_f)
        )

        external_neighbors_a = external_neighbors(network, old_port_a, pipe_piece)
        external_neighbors_b = external_neighbors(network, old_port_b, pipe_piece)
        old_group = pipe_piece.group

        ModelOperation.run(model: model, network: network, name: "Insert Master Flow Wye Saddle") do |operation|
          old_group.erase! if old_group && old_group.valid?
          network.remove_piece(pipe_piece)

          pipe_a = build_pipe_piece(
            model: model, network: network,
            start_point: point_a, end_point: center,
            dimensions: dims, catalog_product: pipe_product,
            hide_end_boundary: true
          )
          pipe_b = build_pipe_piece(
            model: model, network: network,
            start_point: center, end_point: point_b,
            dimensions: dims, catalog_product: pipe_product,
            hide_start_boundary: true
          )
          operation.abort!(nil) unless pipe_a && pipe_b

          group = model.active_entities.add_group
          group.name = "Master Flow #{product.sku} — 45-Degree Wye Saddle"
          geometry = Catalog::MasterFlowGeometry.build_round_wye_saddle(
            group: group,
            center: center,
            main_vector: main,
            side_vector: side,
            main_diameter: dims.diameter,
            product: product,
            forward_sign: forward_sign
          )
          unless geometry
            group.erase! if group.valid?
            operation.abort!(nil)
          end

          main_a_port = Model::Port.new(
            point: center,
            vector: main.clone.reverse,
            shape: :round,
            diameter: dims.diameter
          )
          main_b_port = Model::Port.new(
            point: center,
            vector: main.clone,
            shape: :round,
            diameter: dims.diameter
          )
          branch_port = Model::Port.new(
            point: geometry[:branch_end],
            vector: geometry[:branch_axis],
            shape: :round,
            diameter: product.branch_diameter.to_f
          )

          wye_piece = Model::DuctPiece.new(
            type: :wye,
            group: group,
            ports: [main_a_port, main_b_port, branch_port]
          )
          network.add_piece(wye_piece)
          PieceMetadataService.save_piece(wye_piece)
          Catalog::Manager.tag_piece(wye_piece, product)

          network.connect_ports(pipe_a.ports[1], main_a_port)
          network.connect_ports(pipe_b.ports[0], main_b_port)
          reconnect_neighbors(network, pipe_a.ports[0], external_neighbors_a)
          reconnect_neighbors(network, pipe_b.ports[1], external_neighbors_b)

          transition = BranchTransitionService.attach(
            model: model,
            network: network,
            source_port: branch_port,
            target_dimensions: requested_branch_dimensions,
            cap_output: true
          )
          operation.abort!(nil) unless transition

          {
            wye_piece: wye_piece,
            branch_port: transition[:output_port],
            native_branch_port: branch_port,
            branch_transition_piece: transition[:piece],
            pipe_a: pipe_a,
            pipe_b: pipe_b
          }
        end
      rescue => error
        puts "InlineWyeInsertService.insert_wye_on_pipe failed: #{error.message}"
        puts error.backtrace.join("\n") if error.backtrace
        nil
      end

      def self.external_neighbors(network, port, piece)
        Array(network.connected_ports(port)).select { |other| other && other.piece != piece }
      rescue
        []
      end
      private_class_method :external_neighbors

      def self.reconnect_neighbors(network, replacement_port, neighbors)
        Array(neighbors).each { |neighbor| network.connect_ports(replacement_port, neighbor) }
      rescue
        nil
      end
      private_class_method :reconnect_neighbors

      def self.build_pipe_piece(
        model:, network:, start_point:, end_point:, dimensions:, catalog_product:,
        hide_start_boundary: false, hide_end_boundary: false
      )
        vector = start_point.vector_to(end_point)
        return nil if vector.length <= 0.000001
        vector.normalize!

        group = model.active_entities.add_group
        group.name = "Master Flow #{catalog_product.sku} — Duct Pipe"
        success = Catalog::MasterFlowGeometry.build_pipe(
          group: group,
          start_point: start_point,
          end_point: end_point,
          dimensions: dimensions,
          product: catalog_product,
          hide_start_boundary: hide_start_boundary,
          hide_end_boundary: hide_end_boundary
        )
        unless success
          group.erase! if group.valid?
          return nil
        end

        start_port = Model::Port.new(
          point: start_point, vector: vector.clone.reverse,
          shape: :round, diameter: dimensions.diameter
        )
        end_port = Model::Port.new(
          point: end_point, vector: vector.clone,
          shape: :round, diameter: dimensions.diameter
        )
        piece = Model::DuctPiece.new(type: :pipe, group: group, ports: [start_port, end_port])
        network.add_piece(piece)
        PieceMetadataService.save_piece(piece)
        Catalog::Manager.tag_piece(
          piece,
          catalog_product,
          "modeled_cut_length" => start_point.distance(end_point)
        )
        piece
      rescue => error
        puts "InlineWyeInsertService.build_pipe_piece failed: #{error.message}"
        nil
      end
      private_class_method :build_pipe_piece
    end
  end
end

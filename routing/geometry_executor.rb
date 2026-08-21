module DuctExtension
  module Services
    class GeometryExecutor
      DICTIONARY = "DuctExtension"

      DEFAULT_BEND_RADIUS_FACTOR = 1.5

      def self.execute(model, steps, network, connect_target_port: nil)
        new(model, network).execute(steps, connect_target_port: connect_target_port)
      end

      def initialize(model, network)
        @model = model
        @network = network
        @last_port = nil
      end

      def execute(steps, connect_target_port: nil)
        steps = Array(steps).compact
        return nil if steps.empty?

        ModelOperation.run(
          model: @model,
          network: @network,
          name: "Draw Orthogonal Duct"
        ) do |operation|
          result = nil

          steps.each do |step|
            result =
              case step.type
              when :pipe
                execute_pipe(step)
              when :elbow
                execute_elbow(step)
              when :reducer
                execute_reducer(step)
              else
                puts "GeometryExecutor: unknown step type #{step.type.inspect}"
                nil
              end

            operation.abort!(nil) unless result
          end

          if connect_target_port
            connection = @network.connect_ports(@last_port, connect_target_port)
            operation.abort!(nil) unless connection
          end

          {
            last_port: @last_port,
            last_piece: result
          }
        end
      rescue => error
        puts "GeometryExecutor.execute failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      private

      def execute_pipe(step)
        dimensions = dimensions_for(step)

        catalog_product = nil
        if Catalog::Manager.active?(@model)
          catalog_product = Catalog::Manager.pipe_product(dimensions, @model)
          return Catalog::Manager.notify_unsupported(:pipe, dimensions) unless catalog_product
        end

        start_point =
          if step[:deferred_start] && @last_port
            @last_port.point
          elsif step[:start_point]
            point3d(step[:start_point])
          elsif step[:source_port]
            step[:source_port].point
          elsif @last_port
            @last_port.point
          else
            nil
          end

        end_point = point3d(step[:end_point])
        return nil unless start_point && end_point

        vector = start_point.vector_to(end_point)
        return nil if vector.length == 0
        vector.normalize!

        source_port = step[:source_port]
        frame_source = source_port || @last_port
        preferred_width_axis = frame_source_width_axis(frame_source)
        preferred_height_axis = frame_source_height_axis(frame_source)

        # One requested straight run is one semantic and visual piece. Catalog
        # package lengths are not part of the modeling abstraction: no segmentation
        # and no virtual joints.
        build_pipe_piece(
          start_point: start_point,
          end_point: end_point,
          dimensions: dimensions,
          catalog_product: catalog_product,
          source_port: source_port,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
      end

      def build_pipe_piece(
        start_point:,
        end_point:,
        dimensions:,
        catalog_product:,
        source_port:,
        preferred_width_axis:,
        preferred_height_axis:
      )
        vector = start_point.vector_to(end_point)
        return nil if vector.length == 0
        vector.normalize!

        group = @model.active_entities.add_group
        group.name =
          if catalog_product
            # One modeled run remains one clean selectable object regardless of
            # length. Package-length variants are not represented in geometry.
            "Master Flow #{catalog_product.sku} — Duct Pipe"
          elsif dimensions[:shape] == :rectangular
            "Rectangular Duct Pipe"
          else
            "Duct Pipe"
          end

        success =
          if catalog_product
            Catalog::MasterFlowGeometry.build_pipe(
              group: group,
              start_point: start_point,
              end_point: end_point,
              dimensions: dimensions,
              product: catalog_product,
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis
            )
          elsif dimensions[:shape] == :rectangular
            Geometry::RectangularPipeBuilder.build_into(
              group,
              start_point,
              end_point,
              dimensions[:width],
              dimensions[:height],
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false,
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis,
              allow_relevel: true
            )
          else
            Geometry::PipeBuilder.build_into(
              group,
              start_point,
              end_point,
              dimensions[:diameter],
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false
            )
          end

        unless success
          group.erase! if group.valid?
          return nil
        end

        basis =
          if dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.stable_basis_for_axis(
              vector,
              dimensions[:width],
              dimensions[:height],
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis,
              allow_relevel: !catalog_product
            )
          else
            nil
          end

        start_port = Model::Port.new(
          point: start_point,
          vector: vector.clone.reverse,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: basis && basis[:width_axis],
          height_axis: basis && basis[:height_axis]
        )

        end_port = Model::Port.new(
          point: end_point,
          vector: vector.clone,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: basis && basis[:width_axis],
          height_axis: basis && basis[:height_axis]
        )

        piece = Model::DuctPiece.new(
          type: :pipe,
          group: group,
          ports: [start_port, end_port]
        )

        @network.add_piece(piece)
        PieceMetadataService.save_piece(piece)

        if catalog_product
          Catalog::Manager.tag_piece(
            piece,
            catalog_product,
            "modeled_run_length" => start_point.distance(end_point),
            "catalog_representation" => "continuous_model_run"
          )
        end

        connect_source_port(source_port, start_port)
        connect_deferred_port(start_port)
        @last_port = end_port
        piece
      rescue => error
        puts "GeometryExecutor.build_pipe_piece failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def execute_elbow(step)
        dimensions = dimensions_for(step)

        catalog_product = nil
        if Catalog::Manager.active?(@model)
          catalog_product = Catalog::Manager.preferred_elbow(@model, dimensions)
          return Catalog::Manager.notify_unsupported(:elbow, dimensions) unless catalog_product
        end

        start_point =
          if step[:start_point]
            point3d(step[:start_point])
          elsif step[:source_port]
            step[:source_port].point
          elsif @last_port
            @last_port.point
          else
            nil
          end

        entry_vector = normalized(step[:entry_vector])
        exit_vector = normalized(step[:exit_vector])

        return nil unless start_point && entry_vector && exit_vector

        elbow_angle = entry_vector.angle_between(exit_vector)
        if catalog_product && !Catalog::Manager.elbow_angle_supported?(catalog_product, dimensions, elbow_angle)
          Sketchup.status_text = Catalog::Manager.elbow_angle_status(catalog_product, dimensions, elbow_angle)
          return nil
        end

        bend_radius = step[:bend_radius].to_f
        bend_radius = default_bend_radius(dimensions) if bend_radius <= 0.0
        bend_radius = Catalog::Manager.elbow_bend_radius(
          catalog_product,
          dimensions,
          bend_radius,
          angle: elbow_angle
        ) if catalog_product

        source_port = step[:source_port]
        frame_source = source_port || @last_port

        preferred_width_axis = frame_source_width_axis(frame_source)
        preferred_height_axis = frame_source_height_axis(frame_source)

        frame_plan = nil
        end_point = nil

        group = @model.active_entities.add_group
        group.name =
          if catalog_product
            "Master Flow #{catalog_product.sku} — Rigid Catalog Elbow"
          elsif dimensions[:shape] == :rectangular
            "Rectangular Duct Elbow"
          else
            "Duct Elbow"
          end

        if catalog_product
          catalog_result = Catalog::MasterFlowGeometry.build_elbow(
            group: group,
            start_point: start_point,
            entry_vector: entry_vector,
            exit_vector: exit_vector,
            dimensions: dimensions,
            product: catalog_product,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )

          unless catalog_result
            group.erase! if group.valid?
            return nil
          end

          end_point = catalog_result[:end_point]
          frame_plan = {
            start_basis: catalog_result[:start_basis],
            end_basis: catalog_result[:end_basis],
            relevel: false
          }
          bend_radius = catalog_result[:bend_radius].to_f if catalog_result[:bend_radius]
        else
          frame_plan =
            if dimensions[:shape] == :rectangular
              Geometry::RectangularElbowBuilder.frame_plan(
                start_point: start_point,
                entry_vector: entry_vector,
                exit_vector: exit_vector,
                bend_radius: bend_radius,
                preferred_width_axis: preferred_width_axis,
                preferred_height_axis: preferred_height_axis,
                width: dimensions[:width],
                height: dimensions[:height],
                allow_relevel: true
              )
            else
              nil
            end

          return nil if dimensions[:shape] == :rectangular && !frame_plan

          success =
            if dimensions[:shape] == :rectangular
              Geometry::RectangularElbowBuilder.build_into(
                group,
                start_point,
                entry_vector,
                exit_vector,
                dimensions[:width],
                dimensions[:height],
                bend_radius,
                cap_start: false,
                cap_end: false,
                preferred_width_axis: preferred_width_axis,
                preferred_height_axis: preferred_height_axis,
                allow_relevel: true,
                frame_plan: frame_plan
              )
            else
              Geometry::ElbowBuilder.build_into(
                group,
                start_point,
                entry_vector,
                exit_vector,
                dimensions[:diameter],
                bend_radius,
                cap_start: false,
                cap_end: false
              )
            end

          unless success
            group.erase! if group.valid?
            return nil
          end

          end_point =
            if dimensions[:shape] == :rectangular
              Geometry::RectangularElbowBuilder.exit_point(
                start_point,
                entry_vector,
                exit_vector,
                bend_radius
              )
            else
              Geometry::ElbowBuilder.exit_point(
                start_point,
                entry_vector,
                exit_vector,
                bend_radius
              )
            end

          unless end_point
            group.erase! if group.valid?
            return nil
          end
        end

        start_basis = frame_plan && frame_plan[:start_basis]
        end_basis = frame_plan && frame_plan[:end_basis]

        start_port = Model::Port.new(
          point: start_point,
          vector: entry_vector.clone.reverse,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: start_basis && start_basis[:width_axis],
          height_axis: start_basis && start_basis[:height_axis]
        )

        end_port = Model::Port.new(
          point: end_point,
          vector: exit_vector.clone,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: end_basis && end_basis[:width_axis],
          height_axis: end_basis && end_basis[:height_axis]
        )

        piece = Model::DuctPiece.new(
          type: :elbow,
          group: group,
          ports: [start_port, end_port]
        )

        @network.add_piece(piece)
        PieceMetadataService.save_piece(piece)
        if catalog_product
          angle_degrees = entry_vector.angle_between(exit_vector) * 180.0 / Math::PI
          Catalog::Manager.tag_piece(
            piece,
            catalog_product,
            "modeled_bend_radius" => bend_radius,
            "modeled_angle_degrees" => angle_degrees
          )
        end

        connect_source_port(source_port, start_port)
        connect_deferred_port(start_port)

        @last_port = end_port

        piece
      end

      def execute_reducer(step)
        start_dimensions = reducer_start_dimensions_for(step)
        end_dimensions = reducer_end_dimensions_for(step)

        return nil unless start_dimensions && end_dimensions

        catalog_product = nil
        if Catalog::Manager.active?(@model)
          catalog_product = Catalog::Manager.transition_product(start_dimensions, end_dimensions, @model)
          return Catalog::Manager.notify_unsupported(:transition, start_dimensions) unless catalog_product
        end

        start_point =
          if step[:deferred_start] && @last_port
            @last_port.point
          elsif step[:start_point]
            point3d(step[:start_point])
          elsif step[:source_port]
            step[:source_port].point
          elsif @last_port
            @last_port.point
          else
            nil
          end

        end_point = point3d(step[:end_point])

        return nil unless start_point && end_point

        vector = start_point.vector_to(end_point)
        return nil if vector.length == 0

        vector.normalize!

        source_port = step[:source_port]
        frame_source = source_port || @last_port

        preferred_width_axis =
          step[:preferred_width_axis] || frame_source_width_axis(frame_source)

        preferred_height_axis =
          step[:preferred_height_axis] || frame_source_height_axis(frame_source)

        group = @model.active_entities.add_group
        group.name = catalog_product ? "Master Flow #{catalog_product.sku} — Transition" : reducer_group_name(start_dimensions, end_dimensions)

        success =
          if catalog_product
            Catalog::MasterFlowGeometry.build_transition(
              group: group,
              start_point: start_point,
              end_point: end_point,
              start_dimensions: start_dimensions,
              end_dimensions: end_dimensions,
              product: catalog_product,
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis
            )
          else
            Geometry::ReducerBuilder.build_into(
              group,
              start_point,
              end_point,
              start_dimensions: start_dimensions,
              end_dimensions: end_dimensions,
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis
            )
          end

        unless success
          group.erase! if group.valid?
          return nil
        end

        transition_basis =
          if start_dimensions[:shape] == :rectangular || end_dimensions[:shape] == :rectangular
            Geometry::RectangularFrame.basis_for_axis(
              vector,
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis
            )
          else
            nil
          end

        start_basis = start_dimensions[:shape] == :rectangular ? transition_basis : nil
        end_basis = end_dimensions[:shape] == :rectangular ? transition_basis : nil

        start_port = Model::Port.new(
          point: start_point,
          vector: vector.clone.reverse,
          diameter: start_dimensions[:diameter],
          shape: start_dimensions[:shape],
          width: start_dimensions[:width],
          height: start_dimensions[:height],
          width_axis: start_basis && start_basis[:width_axis],
          height_axis: start_basis && start_basis[:height_axis]
        )

        end_port = Model::Port.new(
          point: end_point,
          vector: vector.clone,
          diameter: end_dimensions[:diameter],
          shape: end_dimensions[:shape],
          width: end_dimensions[:width],
          height: end_dimensions[:height],
          width_axis: end_basis && end_basis[:width_axis],
          height_axis: end_basis && end_basis[:height_axis]
        )

        piece = Model::DuctPiece.new(
          type: :reducer,
          group: group,
          ports: [start_port, end_port]
        )

        @network.add_piece(piece)
        PieceMetadataService.save_piece(piece)
        Catalog::Manager.tag_piece(
          piece,
          catalog_product,
          "modeled_transition_length" => start_point.distance(end_point)
        ) if catalog_product

        connect_source_port(source_port, start_port)
        connect_deferred_port(start_port)

        @last_port = end_port

        piece
      rescue => error
        puts "GeometryExecutor.execute_reducer failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def connect_source_port(source_port, new_start_port)
        return unless source_port
        return unless new_start_port

        @network.connect_ports(source_port, new_start_port)
      end

      def connect_deferred_port(new_start_port)
        return unless @last_port
        return unless new_start_port
        return if @last_port == new_start_port

        if @last_port.point.distance(new_start_port.point) <= Model::Network::CONNECTION_DISTANCE * 4.0
          @network.connect_ports(@last_port, new_start_port)
        end
      end

      def dimensions_for(step)
        Model::Port.dimensions_from_params(step.params)
      end

      def reducer_start_dimensions_for(step)
        params =
          if step[:start_dimensions]
            step[:start_dimensions]
          else
            step.params
          end

        Model::Port.dimensions_from_params(params || {})
      rescue
        nil
      end

      def reducer_end_dimensions_for(step)
        params =
          if step[:end_dimensions]
            step[:end_dimensions]
          else
            step.params
          end

        Model::Port.dimensions_from_params(params || {})
      rescue
        nil
      end

      def reducer_group_name(start_dimensions, end_dimensions)
        start_shape = start_dimensions[:shape].to_sym
        end_shape = end_dimensions[:shape].to_sym

        if start_shape != end_shape
          return start_shape == :rectangular ?
            "Rectangular to Round Transition" :
            "Round to Rectangular Transition"
        end

        start_shape == :rectangular ?
          "Rectangular Duct Increaser / Reducer" :
          "Duct Increaser / Reducer"
      rescue
        "Duct Transition"
      end

      def default_bend_radius(dimensions)
        largest = [
          dimensions[:diameter].to_f,
          dimensions[:width].to_f,
          dimensions[:height].to_f
        ].max

        largest * DEFAULT_BEND_RADIUS_FACTOR
      end

      def point3d(value)
        return value if value.is_a?(Geom::Point3d)

        if value.respond_to?(:to_a)
          Geom::Point3d.new(value.to_a)
        else
          nil
        end
      rescue
        nil
      end

      def normalized(value)
        Geometry::VectorMath.normalized(value)
      end

      def frame_source_width_axis(frame_source)
        if frame_source && frame_source.respond_to?(:width_axis)
          frame_source.width_axis
        else
          nil
        end
      rescue
        nil
      end

      def frame_source_height_axis(frame_source)
        if frame_source && frame_source.respond_to?(:height_axis)
          frame_source.height_axis
        else
          nil
        end
      rescue
        nil
      end
    end
  end
end

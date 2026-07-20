module DuctExtension
  module Services
    class PortToPortRouteService
      MIN_ROUTE_LENGTH = 0.75
      DIRECTION_MATCH_DOT = 0.98
      TARGET_ALIGNMENT_DOT = 0.965
      DEFAULT_BEND_RADIUS_FACTOR = 1.5
      TWO_TERMINAL_MISS_TOLERANCE = 0.05

      WYE_TARGET_SOCKET_LEAD_FACTORS = [1.15, 1.55, 2.0, 2.6]
      WYE_BRIDGE_DIRECTION_DOT = 0.50
      WYE_SOCKET_ALIGNMENT_BONUS = 20.0

      def self.connect(
        model:,
        network:,
        source_port:,
        source_point:,
        target_port:,
        diameter:,
        shape: :round,
        width: nil,
        height: nil,
        fitting_mode: :elbow
      )
        return nil unless model && network && target_port

        start_port = source_port

        start_point =
          if start_port
            start_port.point
          elsif source_point
            source_point
          else
            nil
          end

        return nil unless start_point
        return nil if start_port && start_port == target_port

        dimensions = Model::Port.dimensions_from_params(
          {
            shape: shape,
            diameter: diameter,
            width: width,
            height: height
          },
          start_port || target_port
        )

        unless start_port
          return connect_loose_point_to_port(
            model: model,
            network: network,
            source_point: start_point,
            target_port: target_port,
            dimensions: dimensions
          )
        end

        target_dimensions = Model::Port.dimensions_from_params({}, target_port)

        routing_target_port = target_port
        passive_reducer_step = nil

        if passive_reducer_needed?(dimensions, target_dimensions)
          reducer_length = passive_reducer_length(dimensions, target_dimensions)
          target_incoming_vector = normalized(target_port.outward_vector.clone.reverse)

          if target_incoming_vector && reducer_length > MIN_ROUTE_LENGTH
            reducer_start_point = target_port.point.offset(target_incoming_vector.clone.reverse, reducer_length)

            routing_target_port = virtual_target_port_for_reducer(
              target_port: target_port,
              point: reducer_start_point,
              dimensions: dimensions
            )

            passive_reducer_step = Model::BuildStep.new(
              :reducer,
              dimensions.merge(
                {
                  deferred_start: true,
                  end_point: target_port.point,
                  start_dimensions: dimensions,
                  end_dimensions: target_dimensions,
                  preferred_width_axis: target_port.width_axis,
                  preferred_height_axis: target_port.height_axis
                }
              )
            )
          end
        end

        steps = route_steps(
          source_port: start_port,
          target_port: routing_target_port,
          dimensions: dimensions,
          fitting_mode: fitting_mode
        )

        return nil unless steps && !steps.empty?

        steps << passive_reducer_step if passive_reducer_step

        build_steps_and_connect(
          model: model,
          network: network,
          target_port: target_port,
          steps: steps
        )
      rescue => error
        puts "PortToPortRouteService.connect failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.route_steps(source_port:, target_port:, dimensions:, fitting_mode: :elbow)
        return nil unless source_port && target_port

        source_vector = normalized(source_port.outward_vector)
        target_incoming_vector = normalized(target_port.outward_vector.clone.reverse)

        return nil unless source_vector && target_incoming_vector

        if direct_connection_possible?(
          source_point: source_port.point,
          source_vector: source_vector,
          target_point: target_port.point,
          target_incoming_vector: target_incoming_vector
        )
          return direct_steps(
            source_port: source_port,
            target_port: target_port,
            dimensions: dimensions
          )
        end

        return nil if fitting_mode == :straight

        if wye_target_port?(target_port)
          wye_steps = wye_target_approach_steps(
            source_port: source_port,
            target_port: target_port,
            dimensions: dimensions
          )

          return wye_steps if wye_steps
        end

        two_terminal_elbow_steps(
          source_port: source_port,
          target_port: target_port,
          dimensions: dimensions
        ) ||
          one_elbow_steps(
            source_port: source_port,
            target_port: target_port,
            dimensions: dimensions
          ) ||
          two_elbow_dogleg_steps(
            source_port: source_port,
            target_port: target_port,
            dimensions: dimensions
          )
      rescue => error
        puts "PortToPortRouteService.route_steps failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.direct_steps(source_port:, target_port:, dimensions:)
        [
          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                source_port: source_port,
                start_point: source_port.point,
                end_point: target_port.point
              }
            )
          )
        ]
      end

      def self.build_steps_and_connect(model:, network:, target_port:, steps:)
        return nil unless steps && !steps.empty?

        result = GeometryExecutor.execute(model, steps, network)
        return nil unless result && result[:last_port]

        network.connect_ports(result[:last_port], target_port)
        network.rebuild_index! if network.respond_to?(:rebuild_index!)

        result
      end

      def self.connect_loose_point_to_port(
        model:,
        network:,
        source_point:,
        target_port:,
        dimensions:
      )
        steps = [
          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                start_point: source_point,
                end_point: target_port.point
              }
            )
          )
        ]

        build_steps_and_connect(
          model: model,
          network: network,
          target_port: target_port,
          steps: steps
        )
      end

      def self.passive_reducer_needed?(active_dimensions, target_dimensions)
        active_dimensions = normalize_dimensions_hash(active_dimensions)
        target_dimensions = normalize_dimensions_hash(target_dimensions)

        return false unless active_dimensions && target_dimensions
        return false unless active_dimensions[:shape] == target_dimensions[:shape]

        if active_dimensions[:shape] == :rectangular
          (active_dimensions[:width].to_f - target_dimensions[:width].to_f).abs > 0.001 ||
            (active_dimensions[:height].to_f - target_dimensions[:height].to_f).abs > 0.001
        else
          (active_dimensions[:diameter].to_f - target_dimensions[:diameter].to_f).abs > 0.001
        end
      rescue
        false
      end

      def self.passive_reducer_length(active_dimensions, target_dimensions)
        if defined?(Geometry::ReducerBuilder) && Geometry::ReducerBuilder.respond_to?(:default_length)
          Geometry::ReducerBuilder.default_length(active_dimensions, target_dimensions).to_f
        else
          active_dimensions = normalize_dimensions_hash(active_dimensions)
          target_dimensions = normalize_dimensions_hash(target_dimensions)

          largest = [
            active_dimensions && active_dimensions[:diameter].to_f,
            active_dimensions && active_dimensions[:width].to_f,
            active_dimensions && active_dimensions[:height].to_f,
            target_dimensions && target_dimensions[:diameter].to_f,
            target_dimensions && target_dimensions[:width].to_f,
            target_dimensions && target_dimensions[:height].to_f
          ].compact.max || 8.0

          largest * 2.1
        end
      rescue
        12.0
      end

      def self.virtual_target_port_for_reducer(target_port:, point:, dimensions:)
        Model::Port.new(
          point: point,
          vector: target_port.outward_vector.clone,
          diameter: dimensions[:diameter],
          shape: dimensions[:shape],
          width: dimensions[:width],
          height: dimensions[:height],
          width_axis: target_port.width_axis,
          height_axis: target_port.height_axis,
          piece: target_port.piece
        )
      rescue
        nil
      end

      def self.normalize_dimensions_hash(dimensions)
        Model::Port.dimensions_from_params(dimensions || {})
      rescue
        nil
      end

      def self.direct_connection_possible?(
        source_point:,
        source_vector:,
        target_point:,
        target_incoming_vector:
      )
        path = source_point.vector_to(target_point)
        return false if path.length <= 0.0

        path.normalize!

        source_dot = source_vector.dot(path)
        target_dot = target_incoming_vector.dot(path)

        source_dot >= DIRECTION_MATCH_DOT &&
          target_dot >= DIRECTION_MATCH_DOT
      end

      def self.wye_target_approach_steps(source_port:, target_port:, dimensions:)
        two_terminal_elbow_steps(
          source_port: source_port,
          target_port: target_port,
          dimensions: dimensions
        )
      end

      def self.two_terminal_elbow_steps(source_port:, target_port:, dimensions:)
        start_point = source_port.point
        target_point = target_port.point

        source_vector = normalized(source_port.outward_vector)
        target_incoming_vector = normalized(target_port.outward_vector.clone.reverse)

        return nil unless source_vector && target_incoming_vector

        bend_radius = bend_radius_for(dimensions)

        candidates = two_terminal_mid_direction_candidates(
          start_point: start_point,
          target_point: target_point,
          source_vector: source_vector,
          target_incoming_vector: target_incoming_vector
        )

        best_steps = nil
        best_score = nil

        candidates.each do |middle_direction|
          middle_direction = normalized(middle_direction)
          next unless middle_direction
          next if middle_direction.parallel?(source_vector)
          next if middle_direction.parallel?(target_incoming_vector)

          first_angle = source_vector.angle_between(middle_direction)
          second_angle = middle_direction.angle_between(target_incoming_vector)

          next unless valid_elbow_angle?(first_angle)
          next unless valid_elbow_angle?(second_angle)

          first_exit = elbow_exit_point(
            start_point,
            source_vector,
            middle_direction,
            bend_radius
          )

          next unless first_exit

          second_delta = elbow_exit_delta(
            entry_vector: middle_direction,
            exit_vector: target_incoming_vector,
            bend_radius: bend_radius
          )

          next unless second_delta

          second_start = target_point.offset(second_delta.reverse)

          bridge = first_exit.vector_to(second_start)
          next if bridge.length < MIN_ROUTE_LENGTH

          bridge_direction = bridge.clone
          bridge_direction.normalize!

          next if bridge_direction.dot(middle_direction) < 0.55

          score =
            bridge.length +
            ((1.0 - bridge_direction.dot(middle_direction)).abs * 16.0) +
            (first_angle * 1.5) +
            (second_angle * 1.5)

          steps = [
            Model::BuildStep.new(
              :elbow,
              dimensions.merge(
                {
                  source_port: source_port,
                  start_point: start_point,
                  entry_vector: source_vector,
                  exit_vector: middle_direction,
                  bend_radius: bend_radius
                }
              )
            ),

            Model::BuildStep.new(
              :pipe,
              dimensions.merge(
                {
                  deferred_start: true,
                  end_point: second_start
                }
              )
            ),

            Model::BuildStep.new(
              :elbow,
              dimensions.merge(
                {
                  start_point: second_start,
                  entry_vector: middle_direction,
                  exit_vector: target_incoming_vector,
                  bend_radius: bend_radius
                }
              )
            )
          ]

          if best_steps.nil? || score < best_score
            best_steps = steps
            best_score = score
          end
        end

        best_steps
      end

      def self.two_terminal_mid_direction_candidates(
        start_point:,
        target_point:,
        source_vector:,
        target_incoming_vector:
      )
        candidates = []

        direct = start_point.vector_to(target_point)

        if direct.length > 0.0
          direct.normalize!
          candidates << direct
          candidates << weighted_sum(direct, 0.80, source_vector, 0.20)
          candidates << weighted_sum(direct, 0.80, target_incoming_vector, 0.20)
          candidates << weighted_sum(direct, 0.60, target_incoming_vector, 0.40)
        end

        candidates << vector_sum(source_vector, target_incoming_vector)
        candidates << target_incoming_vector

        axis_candidates.each do |axis|
          candidates << axis
        end

        unique_directions(candidates)
      end

      def self.one_elbow_steps(source_port:, target_port:, dimensions:)
        start_point = source_port.point
        target_point = target_port.point

        source_vector = normalized(source_port.outward_vector)
        target_incoming_vector = normalized(target_port.outward_vector.clone.reverse)

        return nil unless source_vector && target_incoming_vector

        bend_radius = bend_radius_for(dimensions)

        direct_target_elbow_steps(
          source_port: source_port,
          start_point: start_point,
          target_point: target_point,
          source_vector: source_vector,
          target_incoming_vector: target_incoming_vector,
          dimensions: dimensions,
          bend_radius: bend_radius
        ) ||
          target_approach_elbow_steps(
            source_port: source_port,
            start_point: start_point,
            target_point: target_point,
            source_vector: source_vector,
            target_incoming_vector: target_incoming_vector,
            dimensions: dimensions,
            bend_radius: bend_radius
          )
      end

      def self.direct_target_elbow_steps(
        source_port:,
        start_point:,
        target_point:,
        source_vector:,
        target_incoming_vector:,
        dimensions:,
        bend_radius:
      )
        path = start_point.vector_to(target_point)
        return nil if path.length < MIN_ROUTE_LENGTH

        path_direction = path.clone
        path_direction.normalize!

        return nil if target_incoming_vector.dot(path_direction) < TARGET_ALIGNMENT_DOT

        source_angle = source_vector.angle_between(path_direction)
        return nil unless valid_elbow_angle?(source_angle)

        elbow_exit = elbow_exit_point(
          start_point,
          source_vector,
          path_direction,
          bend_radius
        )

        return nil unless elbow_exit

        remaining = elbow_exit.vector_to(target_point)
        return nil if remaining.length < MIN_ROUTE_LENGTH

        remaining_direction = remaining.clone
        remaining_direction.normalize!

        return nil if remaining_direction.dot(path_direction) < TARGET_ALIGNMENT_DOT

        [
          Model::BuildStep.new(
            :elbow,
            dimensions.merge(
              {
                source_port: source_port,
                start_point: start_point,
                entry_vector: source_vector,
                exit_vector: path_direction,
                bend_radius: bend_radius
              }
            )
          ),

          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                deferred_start: true,
                end_point: target_point
              }
            )
          )
        ]
      end

      def self.target_approach_elbow_steps(
        source_port:,
        start_point:,
        target_point:,
        source_vector:,
        target_incoming_vector:,
        dimensions:,
        bend_radius:
      )
        final_direction = target_incoming_vector.clone
        final_direction.normalize!

        source_angle = source_vector.angle_between(final_direction)
        return nil unless valid_elbow_angle?(source_angle)

        elbow_exit = elbow_exit_point(
          start_point,
          source_vector,
          final_direction,
          bend_radius
        )

        return nil unless elbow_exit

        remaining = elbow_exit.vector_to(target_point)
        return nil if remaining.length < MIN_ROUTE_LENGTH

        remaining_direction = remaining.clone
        remaining_direction.normalize!

        return nil if remaining_direction.dot(final_direction) < TARGET_ALIGNMENT_DOT

        [
          Model::BuildStep.new(
            :elbow,
            dimensions.merge(
              {
                source_port: source_port,
                start_point: start_point,
                entry_vector: source_vector,
                exit_vector: final_direction,
                bend_radius: bend_radius
              }
            )
          ),

          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                deferred_start: true,
                end_point: target_point
              }
            )
          )
        ]
      end

      def self.two_elbow_dogleg_steps(source_port:, target_port:, dimensions:)
        start_point = source_port.point
        target_point = target_port.point

        source_vector = normalized(source_port.outward_vector)
        final_direction = normalized(target_port.outward_vector.clone.reverse)

        return nil unless source_vector && final_direction

        bend_radius = bend_radius_for(dimensions)

        candidates = axis_candidates

        best_steps = nil
        best_score = nil

        candidates.each do |dogleg_direction|
          dogleg_direction = normalized(dogleg_direction)
          next unless dogleg_direction

          next if dogleg_direction.parallel?(source_vector)
          next if dogleg_direction.parallel?(final_direction)

          first_exit = elbow_exit_point(
            start_point,
            source_vector,
            dogleg_direction,
            bend_radius
          )

          next unless first_exit

          second_delta = elbow_exit_delta(
            entry_vector: dogleg_direction,
            exit_vector: final_direction,
            bend_radius: bend_radius
          )

          next unless second_delta

          target_line_point = target_point.offset(second_delta.reverse)

          closest = closest_points_between_lines(
            point_a: first_exit,
            dir_a: dogleg_direction,
            point_b: target_line_point,
            dir_b: final_direction.clone.reverse
          )

          next unless closest

          second_start = closest[:point_a]
          target_side_point = closest[:point_b]

          miss = second_start.distance(target_side_point)
          next if miss > TWO_TERMINAL_MISS_TOLERANCE

          first_straight_length = first_exit.distance(second_start)
          next if first_straight_length < MIN_ROUTE_LENGTH

          second_exit = second_start.offset(second_delta)
          final_length = second_exit.distance(target_point)
          next if final_length < MIN_ROUTE_LENGTH

          final_vector = second_exit.vector_to(target_point)
          final_vector.normalize!

          next if final_vector.dot(final_direction) < TARGET_ALIGNMENT_DOT

          score = first_straight_length + final_length + (miss * 8.0)

          steps = [
            Model::BuildStep.new(
              :elbow,
              dimensions.merge(
                {
                  source_port: source_port,
                  start_point: start_point,
                  entry_vector: source_vector,
                  exit_vector: dogleg_direction,
                  bend_radius: bend_radius
                }
              )
            ),

            Model::BuildStep.new(
              :pipe,
              dimensions.merge(
                {
                  deferred_start: true,
                  end_point: second_start
                }
              )
            ),

            Model::BuildStep.new(
              :elbow,
              dimensions.merge(
                {
                  start_point: second_start,
                  entry_vector: dogleg_direction,
                  exit_vector: final_direction,
                  bend_radius: bend_radius
                }
              )
            ),

            Model::BuildStep.new(
              :pipe,
              dimensions.merge(
                {
                  deferred_start: true,
                  end_point: target_point
                }
              )
            )
          ]

          if best_steps.nil? || score < best_score
            best_steps = steps
            best_score = score
          end
        end

        best_steps
      end

      def self.axis_candidates
        directions = []

        base = [
          Geom::Vector3d.new(1, 0, 0),
          Geom::Vector3d.new(0, 1, 0),
          Geom::Vector3d.new(0, 0, 1)
        ]

        base.each do |vector|
          directions << vector
          directions << vector.clone.reverse
        end

        directions
      end

      def self.elbow_exit_delta(entry_vector:, exit_vector:, bend_radius:)
        origin = Geom::Point3d.new(0, 0, 0)

        exit_point = elbow_exit_point(
          origin,
          entry_vector,
          exit_vector,
          bend_radius
        )

        return nil unless exit_point

        origin.vector_to(exit_point)
      end

      def self.closest_points_between_lines(point_a:, dir_a:, point_b:, dir_b:)
        p1 = point_a
        d1 = normalized(dir_a)

        p2 = point_b
        d2 = normalized(dir_b)

        return nil unless p1 && p2 && d1 && d2

        r = p1.vector_to(p2)

        a = d1.dot(d1)
        e = d2.dot(d2)
        b = d1.dot(d2)
        c = d1.dot(r)
        f = d2.dot(r)

        denominator = a * e - b * b

        if denominator.abs < 0.000001
          s = c / a
          t = 0.0
        else
          s = (b * f - c * e) / denominator
          t = (a * f - b * c) / denominator
        end

        {
          point_a: p1.offset(d1, s),
          point_b: p2.offset(d2, t),
          s: s,
          t: t
        }
      rescue
        nil
      end

      def self.bend_radius_for(dimensions)
        largest_dimension_for(dimensions) * DEFAULT_BEND_RADIUS_FACTOR
      end

      def self.largest_dimension_for(dimensions)
        Model::DimensionUtils.largest(dimensions)
      end

      def self.valid_elbow_angle?(angle)
        angle > 0.01 && angle < Math::PI - 0.01
      end

      def self.elbow_exit_point(start_point, entry_vector, exit_vector, bend_radius)
        if defined?(Geometry::ElbowBuilder) &&
           Geometry::ElbowBuilder.respond_to?(:exit_point)

          return Geometry::ElbowBuilder.exit_point(
            start_point,
            entry_vector,
            exit_vector,
            bend_radius
          )
        end

        entry = normalized(entry_vector)
        exitv = normalized(exit_vector)

        return nil unless entry && exitv

        angle = entry.angle_between(exitv)
        return nil unless valid_elbow_angle?(angle)

        normal = entry.cross(exitv)
        return nil if normal.length == 0
        normal.normalize!

        center_offset = normal.cross(entry)
        return nil if center_offset.length == 0
        center_offset.normalize!

        center = start_point.offset(center_offset, bend_radius)
        rotation = Geom::Transformation.rotation(center, normal, angle)

        start_point.transform(rotation)
      rescue
        nil
      end

      def self.vector_sum(vector_a, vector_b)
        a = normalized(vector_a)
        b = normalized(vector_b)

        return nil unless a && b

        result = Geom::Vector3d.new(
          a.x + b.x,
          a.y + b.y,
          a.z + b.z
        )

        return nil if result.length <= 0.000001

        result.normalize!
        result
      rescue
        nil
      end

      def self.weighted_sum(vector_a, weight_a, vector_b, weight_b)
        a = normalized(vector_a)
        b = normalized(vector_b)

        return nil unless a && b

        result = Geom::Vector3d.new(
          (a.x * weight_a.to_f) + (b.x * weight_b.to_f),
          (a.y * weight_a.to_f) + (b.y * weight_b.to_f),
          (a.z * weight_a.to_f) + (b.z * weight_b.to_f)
        )

        return nil if result.length <= 0.000001

        result.normalize!
        result
      rescue
        nil
      end

      def self.unique_directions(directions)
        unique = []

        directions.compact.each do |direction|
          normalized_direction = normalized(direction)
          next unless normalized_direction

          duplicate = unique.any? do |existing|
            existing.dot(normalized_direction).abs > 0.999
          end

          unique << normalized_direction unless duplicate
        end

        unique
      end

      def self.wye_target_port?(target_port)
        return false unless target_port
        return false unless target_port.piece

        target_port.piece.type.to_s.include?("wye")
      rescue
        false
      end

      def self.normalized(vector)
        Geometry::VectorMath.normalized(vector)
      end

      private_class_method :direct_steps
      private_class_method :build_steps_and_connect
      private_class_method :connect_loose_point_to_port
      private_class_method :passive_reducer_needed?
      private_class_method :passive_reducer_length
      private_class_method :virtual_target_port_for_reducer
      private_class_method :normalize_dimensions_hash
      private_class_method :direct_connection_possible?
      private_class_method :wye_target_approach_steps
      private_class_method :two_terminal_elbow_steps
      private_class_method :two_terminal_mid_direction_candidates
      private_class_method :one_elbow_steps
      private_class_method :direct_target_elbow_steps
      private_class_method :target_approach_elbow_steps
      private_class_method :two_elbow_dogleg_steps
      private_class_method :axis_candidates
      private_class_method :elbow_exit_delta
      private_class_method :closest_points_between_lines
      private_class_method :bend_radius_for
      private_class_method :largest_dimension_for
      private_class_method :valid_elbow_angle?
      private_class_method :elbow_exit_point
      private_class_method :vector_sum
      private_class_method :weighted_sum
      private_class_method :unique_directions
      private_class_method :wye_target_port?
      private_class_method :normalized
    end
  end
end

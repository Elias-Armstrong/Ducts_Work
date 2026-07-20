module DuctExtension
  module Services
    class RoutePlanner
      MIN_ELBOW_ANGLE = 0.01
      MAX_ELBOW_ANGLE = Math::PI - 0.01
      DEFAULT_BEND_RADIUS_FACTOR = 1.5

      MIN_SEGMENT_FACTOR = 0.18
      MIN_SEGMENT_ABSOLUTE = 0.75
      MIN_REMAINING_AFTER_ELBOW_DOT = 0.01

      TEE_EXIT_STUB_FACTOR = 0.75
      TEE_EXIT_STUB_ABSOLUTE = 1.0

      RECTANGULAR_TEE_EXIT_STUB_FACTOR = 1.15
      RECTANGULAR_TEE_EXIT_STUB_ABSOLUTE = 1.5

      def self.plan(
        network:,
        start_port:,
        start_point:,
        target_point:,
        diameter:,
        fitting_mode:,
        shape: :round,
        width: nil,
        height: nil
      )
        steps = []

        dimensions = Model::Port.dimensions_from_params(
          {
            shape: shape,
            diameter: diameter,
            width: width,
            height: height
          },
          start_port
        )

        min_length = minimum_segment_length_for(dimensions)

        if start_port
          start = start_port.point
          requested_vector = start.vector_to(target_point)

          return [] if requested_vector.length < min_length

          requested_direction = requested_vector.clone
          requested_direction.normalize!

          start_vector = start_vector_for_port(start_port)
          return [] unless start_vector

          turn_angle = start_vector.angle_between(requested_direction)

          if fitting_mode == :elbow && valid_elbow_angle?(turn_angle)
            if tee_port?(start_port)
              tee_steps = plan_from_tee_port_with_exit_stub(
                start_port: start_port,
                start_point: start,
                start_vector: start_vector,
                requested_direction: requested_direction,
                requested_target: target_point,
                dimensions: dimensions,
                min_length: min_length
              )

              return tee_steps if tee_steps && !tee_steps.empty?
            end

            normal_steps = plan_standard_elbow_route(
              source_port: start_port,
              start_point: start,
              start_vector: start_vector,
              requested_direction: requested_direction,
              requested_target: target_point,
              dimensions: dimensions,
              min_length: min_length
            )

            return normal_steps if normal_steps && !normal_steps.empty?

            puts "Route skipped: target is too close for a clean elbow."
            return []
          end

          if tee_port?(start_port)
            tee_straight_steps = plan_straight_from_tee_port(
              start_port: start_port,
              start_point: start,
              start_vector: start_vector,
              requested_target: target_point,
              dimensions: dimensions,
              min_length: min_length
            )

            return tee_straight_steps if tee_straight_steps && !tee_straight_steps.empty?
          end

          steps << Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                source_port: start_port,
                start_point: start,
                end_point: target_point
              }
            )
          )

          return steps
        end

        if start_point
          vector = start_point.vector_to(target_point)
          return [] if vector.length < min_length

          steps << Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                start_point: start_point,
                end_point: target_point
              }
            )
          )
        end

        steps
      end

      def self.plan_from_tee_port_with_exit_stub(
        start_port:,
        start_point:,
        start_vector:,
        requested_direction:,
        requested_target:,
        dimensions:,
        min_length:
      )
        stub_length = tee_exit_stub_length_for(dimensions)

        total_requested_length = start_point.distance(requested_target)
        max_reasonable_stub = total_requested_length * 0.4
        stub_length = [stub_length, max_reasonable_stub].min

        return nil if stub_length < min_length

        stub_end = start_point.offset(start_vector, stub_length)

        bend_radius = bend_radius_for(dimensions)

        elbow_exit = elbow_exit_point(
          stub_end,
          start_vector,
          requested_direction,
          bend_radius
        )

        return nil unless elbow_exit

        aligned_pipe_end = aligned_pipe_end_after_elbow(
          elbow_exit: elbow_exit,
          requested_target: requested_target,
          exit_direction: requested_direction,
          min_length: min_length
        )

        return nil unless aligned_pipe_end

        [
          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                source_port: start_port,
                start_point: start_point,
                end_point: stub_end
              }
            )
          ),

          Model::BuildStep.new(
            :elbow,
            dimensions.merge(
              {
                start_point: stub_end,
                entry_vector: start_vector,
                exit_vector: requested_direction,
                bend_radius: bend_radius
              }
            )
          ),

          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                deferred_start: true,
                end_point: aligned_pipe_end
              }
            )
          )
        ]
      end

      def self.plan_straight_from_tee_port(
        start_port:,
        start_point:,
        start_vector:,
        requested_target:,
        dimensions:,
        min_length:
      )
        target_vector = start_point.vector_to(requested_target)
        return nil if target_vector.length < min_length

        target_direction = target_vector.clone
        target_direction.normalize!

        return nil if start_vector.angle_between(target_direction) > MIN_ELBOW_ANGLE

        stub_length = tee_exit_stub_length_for(dimensions)

        total_requested_length = start_point.distance(requested_target)
        max_reasonable_stub = total_requested_length * 0.45
        stub_length = [stub_length, max_reasonable_stub].min

        return nil if stub_length < min_length

        stub_end = start_point.offset(start_vector, stub_length)
        return nil if stub_end.distance(requested_target) < min_length

        [
          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                source_port: start_port,
                start_point: start_point,
                end_point: stub_end
              }
            )
          ),

          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                start_point: stub_end,
                end_point: requested_target
              }
            )
          )
        ]
      end

      def self.plan_standard_elbow_route(
        source_port:,
        start_point:,
        start_vector:,
        requested_direction:,
        requested_target:,
        dimensions:,
        min_length:
      )
        bend_radius = bend_radius_for(dimensions)

        elbow_exit = elbow_exit_point(
          start_point,
          start_vector,
          requested_direction,
          bend_radius
        )

        return nil unless elbow_exit

        aligned_pipe_end = aligned_pipe_end_after_elbow(
          elbow_exit: elbow_exit,
          requested_target: requested_target,
          exit_direction: requested_direction,
          min_length: min_length
        )

        return nil unless aligned_pipe_end

        [
          Model::BuildStep.new(
            :elbow,
            dimensions.merge(
              {
                source_port: source_port,
                start_point: start_point,
                entry_vector: start_vector,
                exit_vector: requested_direction,
                bend_radius: bend_radius
              }
            )
          ),

          Model::BuildStep.new(
            :pipe,
            dimensions.merge(
              {
                deferred_start: true,
                end_point: aligned_pipe_end
              }
            )
          )
        ]
      end

      def self.bend_radius_for(dimensions)
        if dimensions[:shape] == :rectangular
          [dimensions[:width].to_f, dimensions[:height].to_f].max * DEFAULT_BEND_RADIUS_FACTOR
        else
          dimensions[:diameter].to_f * DEFAULT_BEND_RADIUS_FACTOR
        end
      end

      def self.tee_exit_stub_length_for(dimensions)
        largest = largest_dimension(dimensions)

        if dimensions[:shape] == :rectangular
          [
            largest * RECTANGULAR_TEE_EXIT_STUB_FACTOR,
            RECTANGULAR_TEE_EXIT_STUB_ABSOLUTE
          ].max
        else
          [
            largest * TEE_EXIT_STUB_FACTOR,
            TEE_EXIT_STUB_ABSOLUTE
          ].max
        end
      end

      def self.start_vector_for_port(port)
        return nil unless port

        vector =
          if port.respond_to?(:outward_vector)
            port.outward_vector
          else
            port.vector
          end

        return nil unless vector

        vector = vector.clone
        return nil if vector.length == 0

        vector.normalize!
        vector
      end

      def self.valid_elbow_angle?(angle)
        angle > MIN_ELBOW_ANGLE && angle < MAX_ELBOW_ANGLE
      end

      def self.minimum_segment_length_for(dimensions)
        largest = largest_dimension(dimensions)

        [largest * MIN_SEGMENT_FACTOR, MIN_SEGMENT_ABSOLUTE].max
      end

      def self.elbow_exit_point(start_point, entry_vector, exit_vector, bend_radius)
        v_in = normalized(entry_vector)
        v_out = normalized(exit_vector)
        return nil unless v_in && v_out

        angle = v_in.angle_between(v_out)
        return nil unless valid_elbow_angle?(angle)

        normal = v_in.cross(v_out)
        return nil if normal.length == 0
        normal.normalize!

        center_offset = normal.cross(v_in)
        return nil if center_offset.length == 0
        center_offset.normalize!

        center = start_point.offset(center_offset, bend_radius)
        rotation = Geom::Transformation.rotation(center, normal, angle)

        start_point.transform(rotation)
      end

      def self.aligned_pipe_end_after_elbow(
        elbow_exit:,
        requested_target:,
        exit_direction:,
        min_length:
      )
        direction = normalized(exit_direction)
        return nil unless direction

        exit_to_target = elbow_exit.vector_to(requested_target)
        return nil if exit_to_target.length == 0

        distance_along_exit = exit_to_target.dot(direction)

        return nil if distance_along_exit < min_length
        return nil if distance_along_exit < MIN_REMAINING_AFTER_ELBOW_DOT

        elbow_exit.offset(direction, distance_along_exit)
      end

      def self.tee_port?(port)
        port &&
          port.piece &&
          port.piece.respond_to?(:type) &&
          port.piece.type == :tee
      end

      def self.largest_dimension(dimensions)
        Model::DimensionUtils.largest(dimensions)
      end

      def self.normalized(vector)
        Geometry::VectorMath.normalized(vector)
      end

      private_class_method :plan_from_tee_port_with_exit_stub
      private_class_method :plan_straight_from_tee_port
      private_class_method :plan_standard_elbow_route
      private_class_method :bend_radius_for
      private_class_method :tee_exit_stub_length_for
      private_class_method :start_vector_for_port
      private_class_method :valid_elbow_angle?
      private_class_method :minimum_segment_length_for
      private_class_method :elbow_exit_point
      private_class_method :aligned_pipe_end_after_elbow
      private_class_method :tee_port?
      private_class_method :largest_dimension
      private_class_method :normalized
    end
  end
end

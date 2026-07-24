module DuctExtension
  module Services
    # Single owner for the geometry/math used to decide where an inline tee is
    # placed and which branch direction it should use. The insertion service is
    # intentionally separate: this class plans; TeeInsertService mutates.
    class TeePlacementCalculator
      MIN_END_CLEARANCE_FACTOR = 0.65
      MIN_END_CLEARANCE_ABSOLUTE = 1.0
      MAX_TEE_SLIDE_FACTOR = 2.5
      MAX_TEE_SLIDE_ABSOLUTE = 12.0
      MIN_BRANCH_LENGTH = 0.25
      FALLBACK_SOCKET_DEPTH_FACTOR = 0.82

      def self.best_placement(
        pipe_start:,
        pipe_end:,
        dimensions:,
        click_point:,
        active_start_point:,
        active_start_port: nil,
        requested_branch_direction: nil
      )
        return nil unless pipe_start && pipe_end && click_point && active_start_point

        main_vector = pipe_start.vector_to(pipe_end)
        return nil if main_vector.length == 0

        pipe_length = main_vector.length
        main_vector.normalize!

        clearance = end_clearance_for(dimensions)
        return nil if pipe_length <= clearance * 2.0

        click_center = projected_center_on_pipe(
          point: click_point,
          pipe_start: pipe_start,
          main_vector: main_vector,
          pipe_length: pipe_length,
          clearance: clearance
        )
        return nil unless click_center

        active_direction = active_direction_for(
          active_start_point: active_start_point,
          active_start_port: active_start_port,
          click_point: click_point
        )

        candidates = build_center_candidates(
          pipe_start: pipe_start,
          main_vector: main_vector,
          pipe_length: pipe_length,
          clearance: clearance,
          dimensions: dimensions,
          click_center: click_center,
          active_start_point: active_start_point,
          active_direction: active_direction,
          requested_branch_direction: requested_branch_direction
        )
        return nil if candidates.empty?

        choose_best_candidate(
          candidates: candidates,
          dimensions: dimensions,
          main_vector: main_vector,
          active_start_point: active_start_point,
          active_direction: active_direction,
          click_center: click_center,
          requested_branch_direction: requested_branch_direction
        )
      rescue => error
        puts "TeePlacementCalculator.best_placement failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def self.project_point_to_segment(point:, line_start:, line_end:)
        axis = line_start.vector_to(line_end)
        return nil if axis.length == 0

        length = axis.length
        axis.normalize!
        distance_along = line_start.vector_to(point).dot(axis)
        return nil if distance_along <= 0.0 || distance_along >= length

        line_start.offset(axis, distance_along)
      rescue
        nil
      end

      def self.rectangular_side_branch_vector(
        tap_point:,
        center:,
        main_vector:,
        fallback_branch_direction:
      )
        basis = Geometry::RectangularFrame.basis_for_axis(main_vector)
        return Geometry::VectorMath.perpendicularized(fallback_branch_direction, main_vector) unless basis

        radial = Geometry::VectorMath.perpendicularized(center.vector_to(tap_point), main_vector)
        return Geometry::VectorMath.perpendicularized(fallback_branch_direction, main_vector) unless radial

        candidates = [
          basis[:width_axis],
          basis[:width_axis].clone.reverse,
          basis[:height_axis],
          basis[:height_axis].clone.reverse
        ]

        best = candidates.max_by { |candidate| candidate.dot(radial) }
        best && best.clone
      rescue
        Geometry::VectorMath.perpendicularized(fallback_branch_direction, main_vector)
      end

      def self.rectangular_branch_base_point(center:, branch_vector:, dimensions:, basis:)
        return center unless basis

        branch = Geometry::VectorMath.normalized(branch_vector)
        return center unless branch

        width_dot = branch.dot(basis[:width_axis]).abs
        height_dot = branch.dot(basis[:height_axis]).abs
        offset = width_dot >= height_dot ? dimensions[:width].to_f / 2.0 : dimensions[:height].to_f / 2.0

        center.offset(branch, offset)
      end

      def self.socket_depth(dimensions)
        if dimensions[:shape] == :rectangular
          Geometry::RectangularTeeBuilder.socket_depth(dimensions[:width], dimensions[:height])
        else
          Geometry::TeeBuilder.socket_depth(dimensions[:diameter])
        end
      rescue
        Model::DimensionUtils.largest(dimensions) * FALLBACK_SOCKET_DEPTH_FACTOR
      end

      def self.end_clearance_for(dimensions)
        [
          Model::DimensionUtils.largest(dimensions) * MIN_END_CLEARANCE_FACTOR,
          MIN_END_CLEARANCE_ABSOLUTE
        ].max
      end

      def self.max_tee_slide_for(dimensions)
        [
          Model::DimensionUtils.largest(dimensions) * MAX_TEE_SLIDE_FACTOR,
          MAX_TEE_SLIDE_ABSOLUTE
        ].max
      end

      def self.build_center_candidates(
        pipe_start:,
        main_vector:,
        pipe_length:,
        clearance:,
        dimensions:,
        click_center:,
        active_start_point:,
        active_direction:,
        requested_branch_direction:
      )
        candidates = [{ center: click_center, source: :click_center }]

        branch_vector_candidates(
          dimensions: dimensions,
          main_vector: main_vector,
          center: click_center,
          active_start_point: active_start_point,
          requested_branch_direction: requested_branch_direction
        ).each do |branch_vector|
          aligned = active_line_aligned_center(
            pipe_start: pipe_start,
            main_vector: main_vector,
            pipe_length: pipe_length,
            clearance: clearance,
            dimensions: dimensions,
            click_center: click_center,
            max_slide: max_tee_slide_for(dimensions),
            active_start_point: active_start_point,
            active_direction: active_direction,
            branch_vector: branch_vector
          )
          candidates << aligned if aligned
        end

        candidates.uniq { |candidate| point_key(candidate[:center]) }
      end
      private_class_method :build_center_candidates

      def self.active_line_aligned_center(
        pipe_start:,
        main_vector:,
        pipe_length:,
        clearance:,
        dimensions:,
        click_center:,
        max_slide:,
        active_start_point:,
        active_direction:,
        branch_vector:
      )
        active_direction = Geometry::VectorMath.normalized(active_direction)
        branch_vector = Geometry::VectorMath.normalized(branch_vector)
        return nil unless active_direction && branch_vector

        socket_offset = socket_offset_vector(
          branch_vector: branch_vector,
          dimensions: dimensions,
          main_vector: main_vector
        )
        return nil unless socket_offset

        closest = Geometry::VectorMath.closest_points_between_lines(
          point_a: pipe_start.offset(socket_offset),
          dir_a: main_vector,
          point_b: active_start_point,
          dir_b: active_direction
        )
        return nil unless closest

        distance_along_pipe = pipe_start.vector_to(closest[:point_a]).dot(main_vector)
        distance_along_pipe = [[distance_along_pipe, clearance].max, pipe_length - clearance].min
        center = pipe_start.offset(main_vector, distance_along_pipe)
        return nil if center.distance(click_center) > max_slide

        {
          center: center,
          branch_vector: branch_vector,
          source: :active_line,
          slide_distance: center.distance(click_center)
        }
      rescue => error
        puts "TeePlacementCalculator.active_line_aligned_center failed: #{error.message}"
        nil
      end
      private_class_method :active_line_aligned_center

      def self.projected_center_on_pipe(point:, pipe_start:, main_vector:, pipe_length:, clearance:)
        return nil unless point

        distance_along = pipe_start.vector_to(point).dot(main_vector)
        distance_along = [[distance_along, clearance].max, pipe_length - clearance].min
        return nil if distance_along <= 0.0 || distance_along >= pipe_length

        pipe_start.offset(main_vector, distance_along)
      end
      private_class_method :projected_center_on_pipe

      def self.choose_best_candidate(
        candidates:,
        dimensions:,
        main_vector:,
        active_start_point:,
        active_direction:,
        click_center:,
        requested_branch_direction:
      )
        best = nil
        best_score = nil

        candidates.each do |candidate|
          center = candidate[:center]
          next unless center

          branch_vectors =
            if candidate[:branch_vector]
              [candidate[:branch_vector]]
            else
              branch_vector_candidates(
                dimensions: dimensions,
                main_vector: main_vector,
                center: center,
                active_start_point: active_start_point,
                requested_branch_direction: requested_branch_direction
              )
            end

          branch_vectors.each do |branch_vector|
            branch_vector = Geometry::VectorMath.normalized(branch_vector)
            next unless branch_vector
            next if main_vector.parallel?(branch_vector)

            socket_point = branch_socket_point(
              center: center,
              branch_vector: branch_vector,
              dimensions: dimensions,
              main_vector: main_vector
            )
            next unless socket_point
            next if socket_point.distance(active_start_point) < MIN_BRANCH_LENGTH

            score = score_candidate(
              center: center,
              socket_point: socket_point,
              branch_vector: branch_vector,
              active_start_point: active_start_point,
              active_direction: active_direction,
              click_center: click_center,
              source: candidate[:source],
              slide_distance: candidate[:slide_distance]
            )
            next unless score

            if best.nil? || score > best_score
              best = {
                center: center,
                branch_vector: branch_vector,
                socket_point: socket_point,
                score: score,
                source: candidate[:source]
              }
              best_score = score
            end
          end
        end

        best
      end
      private_class_method :choose_best_candidate

      def self.score_candidate(
        center:,
        socket_point:,
        branch_vector:,
        active_start_point:,
        active_direction:,
        click_center:,
        source:,
        slide_distance:
      )
        from_socket_to_active = socket_point.vector_to(active_start_point)
        return nil if from_socket_to_active.length == 0
        from_socket_to_active.normalize!

        tee_alignment = from_socket_to_active.dot(branch_vector)
        active_alignment = 0.0

        if active_direction
          active_to_socket = active_start_point.vector_to(socket_point)
          if active_to_socket.length > 0
            active_to_socket.normalize!
            active_alignment = active_direction.dot(active_to_socket)
          end
        end

        click_closeness = 1.0 / (1.0 + center.distance(click_center))
        source_bonus = source == :active_line ? 0.35 : 0.0
        slide_penalty = (slide_distance || 0.0) * 0.015

        tee_alignment + active_alignment * 0.4 + click_closeness * 0.4 + source_bonus - slide_penalty
      end
      private_class_method :score_candidate

      def self.branch_vector_candidates(
        dimensions:,
        main_vector:,
        center:,
        active_start_point:,
        requested_branch_direction:
      )
        if dimensions[:shape] == :rectangular
          rectangular_branch_vector_candidates(
            main_vector: main_vector,
            center: center,
            active_start_point: active_start_point,
            requested_branch_direction: requested_branch_direction
          )
        else
          round_branch_vector_candidates(
            main_vector: main_vector,
            center: center,
            active_start_point: active_start_point,
            requested_branch_direction: requested_branch_direction
          )
        end
      end
      private_class_method :branch_vector_candidates

      def self.round_branch_vector_candidates(
        main_vector:,
        center:,
        active_start_point:,
        requested_branch_direction:
      )
        candidates = []
        toward_active = Geometry::VectorMath.perpendicularized(center.vector_to(active_start_point), main_vector)
        candidates << toward_active if toward_active

        requested = Geometry::VectorMath.perpendicularized(requested_branch_direction, main_vector)
        candidates << requested if requested
        candidates << requested.clone.reverse if requested

        fallback = fallback_perpendicular(main_vector)
        candidates << fallback if fallback
        candidates << fallback.clone.reverse if fallback

        Geometry::VectorMath.unique_directions(candidates)
      end
      private_class_method :round_branch_vector_candidates

      def self.rectangular_branch_vector_candidates(
        main_vector:,
        center:,
        active_start_point:,
        requested_branch_direction:
      )
        basis = Geometry::RectangularFrame.basis_for_axis(main_vector)
        unless basis
          fallback = Geometry::VectorMath.perpendicularized(requested_branch_direction, main_vector)
          return fallback ? [fallback] : []
        end

        toward_active = Geometry::VectorMath.perpendicularized(center.vector_to(active_start_point), main_vector)
        side_vectors = [
          basis[:width_axis],
          basis[:width_axis].clone.reverse,
          basis[:height_axis],
          basis[:height_axis].clone.reverse
        ]
        side_vectors.sort_by! { |candidate| -candidate.dot(toward_active) } if toward_active

        requested = Geometry::VectorMath.perpendicularized(requested_branch_direction, main_vector)
        candidates = []
        candidates << requested if requested
        candidates << requested.clone.reverse if requested
        candidates.concat(side_vectors)

        Geometry::VectorMath.unique_directions(candidates)
      end
      private_class_method :rectangular_branch_vector_candidates

      def self.branch_socket_point(center:, branch_vector:, dimensions:, main_vector:)
        depth = socket_depth(dimensions)

        if dimensions[:shape] == :rectangular
          basis = Geometry::RectangularFrame.basis_for_axis(main_vector)
          branch_base = basis ? rectangular_branch_base_point(
            center: center,
            branch_vector: branch_vector,
            dimensions: dimensions,
            basis: basis
          ) : center
          branch_base.offset(branch_vector, depth)
        else
          center.offset(branch_vector, depth)
        end
      end
      private_class_method :branch_socket_point

      def self.socket_offset_vector(branch_vector:, dimensions:, main_vector:)
        branch_vector = Geometry::VectorMath.normalized(branch_vector)
        return nil unless branch_vector

        depth = socket_depth(dimensions)
        vector_length = depth

        if dimensions[:shape] == :rectangular
          basis = Geometry::RectangularFrame.basis_for_axis(main_vector)
          if basis
            width_dot = branch_vector.dot(basis[:width_axis]).abs
            height_dot = branch_vector.dot(basis[:height_axis]).abs
            vector_length += width_dot >= height_dot ? dimensions[:width].to_f / 2.0 : dimensions[:height].to_f / 2.0
          end
        end

        Geom::Vector3d.new(
          branch_vector.x * vector_length,
          branch_vector.y * vector_length,
          branch_vector.z * vector_length
        )
      end
      private_class_method :socket_offset_vector

      def self.active_direction_for(active_start_point:, active_start_port:, click_point:)
        if active_start_port && active_start_port.respond_to?(:outward_vector)
          direction = Geometry::VectorMath.normalized(active_start_port.outward_vector)
          return direction if direction
        end

        return Geometry::VectorMath.normalized(active_start_point.vector_to(click_point)) if active_start_point && click_point

        nil
      end
      private_class_method :active_direction_for

      def self.fallback_perpendicular(axis)
        axis = Geometry::VectorMath.normalized(axis)
        return nil unless axis

        [
          Geom::Vector3d.new(0, 0, 1),
          Geom::Vector3d.new(1, 0, 0),
          Geom::Vector3d.new(0, 1, 0)
        ].each do |candidate|
          result = Geometry::VectorMath.perpendicularized(candidate, axis)
          return result if result
        end

        nil
      end
      private_class_method :fallback_perpendicular

      def self.point_key(point)
        [point.x.round(4), point.y.round(4), point.z.round(4)]
      end
      private_class_method :point_key
    end
  end
end

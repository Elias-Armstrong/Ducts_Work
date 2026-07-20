module DuctExtension
  module Services
    module PipeTargetConnectionService
      MIN_END_CLEARANCE_FACTOR = 0.65
      MIN_END_CLEARANCE_ABSOLUTE = 1.0

      MAX_TEE_SLIDE_FACTOR = 2.5
      MAX_TEE_SLIDE_ABSOLUTE = 12.0

      MIN_BRANCH_LENGTH = 0.25

      def self.insert_smart_tee_target(
        model:,
        network:,
        target_pipe_piece:,
        click_point:,
        active_start_point:,
        active_start_port: nil,
        requested_branch_direction: nil
      )
        return nil unless model && network
        return nil unless target_pipe_piece
        return nil unless target_pipe_piece.type == :pipe
        return nil unless target_pipe_piece.ports && target_pipe_piece.ports.length == 2
        return nil unless click_point && active_start_point

        port_a = target_pipe_piece.ports[0]
        port_b = target_pipe_piece.ports[1]

        dimensions = Model::Port.dimensions_from_params({}, port_a)

        pipe_start = port_a.point
        pipe_end = port_b.point

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

        best = choose_best_candidate(
          candidates: candidates,
          dimensions: dimensions,
          main_vector: main_vector,
          active_start_point: active_start_point,
          active_direction: active_direction,
          click_center: click_center,
          requested_branch_direction: requested_branch_direction
        )

        return nil unless best

        TeeInsertService.insert_tee_on_pipe(
          model: model,
          network: network,
          pipe_piece: target_pipe_piece,
          tap_point: best[:center],
          branch_direction: best[:branch_vector]
        )
      rescue => error
        puts "PipeTargetConnectionService.insert_smart_tee_target failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
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
        candidates = []

        candidates << {
          center: click_center,
          source: :click_center
        }

        branch_vectors = branch_vector_candidates(
          dimensions: dimensions,
          main_vector: main_vector,
          center: click_center,
          active_start_point: active_start_point,
          requested_branch_direction: requested_branch_direction
        )

        max_slide = max_tee_slide_for(dimensions)

        branch_vectors.each do |branch_vector|
          aligned = active_line_aligned_center(
            pipe_start: pipe_start,
            main_vector: main_vector,
            pipe_length: pipe_length,
            clearance: clearance,
            dimensions: dimensions,
            click_center: click_center,
            max_slide: max_slide,
            active_start_point: active_start_point,
            active_direction: active_direction,
            branch_vector: branch_vector
          )

          candidates << aligned if aligned
        end

        candidates.uniq { |candidate| point_key(candidate[:center]) }
      end

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
        active_direction = normalized(active_direction)
        branch_vector = normalized(branch_vector)

        return nil unless active_direction && branch_vector

        socket_offset = socket_offset_vector(
          branch_vector: branch_vector,
          dimensions: dimensions,
          main_vector: main_vector
        )

        return nil unless socket_offset

        offset_pipe_point = pipe_start.offset(socket_offset)

        closest = closest_points_between_lines(
          point_a: offset_pipe_point,
          dir_a: main_vector,
          point_b: active_start_point,
          dir_b: active_direction
        )

        return nil unless closest

        socket_on_target_line = closest[:point_a]

        from_pipe_start = pipe_start.vector_to(socket_on_target_line)
        distance_along_pipe = from_pipe_start.dot(main_vector)

        distance_along_pipe = [
          [distance_along_pipe, clearance].max,
          pipe_length - clearance
        ].min

        center = pipe_start.offset(main_vector, distance_along_pipe)

        # Critical anti-jump rule:
        # The tee may slide to make a clean connection, but it may not teleport
        # far away from the pipe location the user actually clicked.
        return nil if center.distance(click_center) > max_slide

        {
          center: center,
          branch_vector: branch_vector,
          source: :active_line,
          slide_distance: center.distance(click_center)
        }
      rescue => error
        puts "PipeTargetConnectionService.active_line_aligned_center failed: #{error.message}"
        nil
      end

      def self.projected_center_on_pipe(
        point:,
        pipe_start:,
        main_vector:,
        pipe_length:,
        clearance:
      )
        return nil unless point

        from_start = pipe_start.vector_to(point)
        distance_along = from_start.dot(main_vector)

        distance_along = [
          [distance_along, clearance].max,
          pipe_length - clearance
        ].min

        return nil if distance_along <= 0.0
        return nil if distance_along >= pipe_length

        pipe_start.offset(main_vector, distance_along)
      end

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
            branch_vector = normalized(branch_vector)
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

        source_bonus =
          case source
          when :active_line
            0.35
          else
            0.0
          end

        slide_penalty = (slide_distance || 0.0) * 0.015

        tee_alignment + active_alignment * 0.4 + click_closeness * 0.4 + source_bonus - slide_penalty
      end

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

      def self.round_branch_vector_candidates(
        main_vector:,
        center:,
        active_start_point:,
        requested_branch_direction:
      )
        candidates = []

        toward_active = center.vector_to(active_start_point)
        toward_active = perpendicularized(toward_active, main_vector)
        candidates << toward_active if toward_active

        requested = perpendicularized(requested_branch_direction, main_vector)
        candidates << requested if requested
        candidates << requested.clone.reverse if requested

        fallback = fallback_perpendicular(main_vector)
        candidates << fallback if fallback
        candidates << fallback.clone.reverse if fallback

        unique_vectors(candidates)
      end

      def self.rectangular_branch_vector_candidates(
        main_vector:,
        center:,
        active_start_point:,
        requested_branch_direction:
      )
        basis = Geometry::RectangularFrame.basis_for_axis(main_vector)

        unless basis
          fallback = perpendicularized(requested_branch_direction, main_vector)
          return fallback ? [fallback] : []
        end

        toward_active = perpendicularized(center.vector_to(active_start_point), main_vector)

        side_vectors = [
          basis[:width_axis],
          basis[:width_axis].clone.reverse,
          basis[:height_axis],
          basis[:height_axis].clone.reverse
        ]

        if toward_active
          side_vectors.sort_by! { |candidate| -candidate.dot(toward_active) }
        end

        requested = perpendicularized(requested_branch_direction, main_vector)

        candidates = []
        candidates << requested if requested
        candidates << requested.clone.reverse if requested
        candidates.concat(side_vectors)

        unique_vectors(candidates)
      end

      def self.branch_socket_point(center:, branch_vector:, dimensions:, main_vector:)
        socket_depth = tee_socket_depth(dimensions)

        if dimensions[:shape] == :rectangular
          basis = Geometry::RectangularFrame.basis_for_axis(main_vector)

          branch_base =
            if basis
              rectangular_branch_base_point(
                center: center,
                branch_vector: branch_vector,
                dimensions: dimensions,
                basis: basis
              )
            else
              center
            end

          branch_base.offset(branch_vector, socket_depth)
        else
          center.offset(branch_vector, socket_depth)
        end
      end

      def self.socket_offset_vector(branch_vector:, dimensions:, main_vector:)
        branch_vector = normalized(branch_vector)
        return nil unless branch_vector

        socket_depth = tee_socket_depth(dimensions)

        if dimensions[:shape] == :rectangular
          basis = Geometry::RectangularFrame.basis_for_axis(main_vector)

          face_offset =
            if basis
              width_dot = branch_vector.dot(basis[:width_axis]).abs
              height_dot = branch_vector.dot(basis[:height_axis]).abs

              if width_dot >= height_dot
                dimensions[:width].to_f / 2.0
              else
                dimensions[:height].to_f / 2.0
              end
            else
              0.0
            end

          vector_length = face_offset + socket_depth
        else
          vector_length = socket_depth
        end

        Geom::Vector3d.new(
          branch_vector.x * vector_length,
          branch_vector.y * vector_length,
          branch_vector.z * vector_length
        )
      end

      def self.active_direction_for(active_start_point:, active_start_port:, click_point:)
        if active_start_port && active_start_port.respond_to?(:outward_vector)
          direction = normalized(active_start_port.outward_vector)
          return direction if direction
        end

        if active_start_point && click_point
          direction = active_start_point.vector_to(click_point)
          return normalized(direction)
        end

        nil
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

      def self.rectangular_branch_base_point(center:, branch_vector:, dimensions:, basis:)
        return center unless basis

        branch = normalized(branch_vector)
        return center unless branch

        width_dot = branch.dot(basis[:width_axis]).abs
        height_dot = branch.dot(basis[:height_axis]).abs

        offset =
          if width_dot >= height_dot
            dimensions[:width].to_f / 2.0
          else
            dimensions[:height].to_f / 2.0
          end

        center.offset(branch, offset)
      end

      def self.tee_socket_depth(dimensions)
        if dimensions[:shape] == :rectangular
          Geometry::RectangularTeeBuilder.socket_depth(
            dimensions[:width],
            dimensions[:height]
          )
        else
          Geometry::TeeBuilder.socket_depth(dimensions[:diameter])
        end
      rescue
        largest_dimension(dimensions) * 0.82
      end

      def self.end_clearance_for(dimensions)
        [
          largest_dimension(dimensions) * MIN_END_CLEARANCE_FACTOR,
          MIN_END_CLEARANCE_ABSOLUTE
        ].max
      end

      def self.max_tee_slide_for(dimensions)
        [
          largest_dimension(dimensions) * MAX_TEE_SLIDE_FACTOR,
          MAX_TEE_SLIDE_ABSOLUTE
        ].max
      end

      def self.largest_dimension(dimensions)
        Model::DimensionUtils.largest(dimensions)
      end

      def self.perpendicularized(vector, axis)
        Geometry::VectorMath.perpendicularized(vector, axis)
      end

      def self.fallback_perpendicular(axis)
        axis = normalized(axis)
        return nil unless axis

        z_axis = Geom::Vector3d.new(0, 0, 1)
        result = perpendicularized(z_axis, axis)

        result ||= perpendicularized(Geom::Vector3d.new(1, 0, 0), axis)
        result ||= perpendicularized(Geom::Vector3d.new(0, 1, 0), axis)

        result
      end

      def self.normalized(vector)
        Geometry::VectorMath.normalized(vector)
      end

      def self.unique_vectors(vectors)
        clean = []

        Array(vectors).each do |vector|
          vector = normalized(vector)
          next unless vector

          duplicate = clean.any? do |existing|
            existing.angle_between(vector) < 0.001
          end

          clean << vector unless duplicate
        end

        clean
      end

      def self.point_key(point)
        [
          point.x.round(4),
          point.y.round(4),
          point.z.round(4)
        ]
      end

      private_class_method :build_center_candidates
      private_class_method :active_line_aligned_center
      private_class_method :projected_center_on_pipe
      private_class_method :choose_best_candidate
      private_class_method :score_candidate
      private_class_method :branch_vector_candidates
      private_class_method :round_branch_vector_candidates
      private_class_method :rectangular_branch_vector_candidates
      private_class_method :branch_socket_point
      private_class_method :socket_offset_vector
      private_class_method :active_direction_for
      private_class_method :closest_points_between_lines
      private_class_method :rectangular_branch_base_point
      private_class_method :tee_socket_depth
      private_class_method :end_clearance_for
      private_class_method :max_tee_slide_for
      private_class_method :largest_dimension
      private_class_method :perpendicularized
      private_class_method :fallback_perpendicular
      private_class_method :normalized
      private_class_method :unique_vectors
      private_class_method :point_key
    end
  end
end

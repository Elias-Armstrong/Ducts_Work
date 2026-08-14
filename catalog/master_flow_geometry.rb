module DuctExtension
  module Catalog
    # Geometry used only when Master Flow catalog mode is active. These builders
    # intentionally favor recognizable fabricated sheet-metal construction:
    # segmented adjustable elbows, hard/mitered rectangular elbows, straight
    # tee/wye shells, hemmed reducers, and visible stock-pipe seams.
    module MasterFlowGeometry
      EPSILON = 0.000001
      ROUND_SEGMENTS = 24
      ELBOW_GORE_COUNT = 4
      ELBOW_SUBDIVISIONS_PER_GORE = 3

      module_function

      def build_pipe(group:, start_point:, end_point:, dimensions:, product:, preferred_width_axis: nil, preferred_height_axis: nil)
        dims = Model::DuctDimensions.coerce(dimensions)
        success =
          if dims.rectangular?
            Geometry::RectangularPipeBuilder.build_into(
              group,
              start_point,
              end_point,
              dims.width,
              dims.height,
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false,
              preferred_width_axis: preferred_width_axis,
              preferred_height_axis: preferred_height_axis,
              allow_relevel: false
            )
          else
            Geometry::PipeBuilder.build_into(
              group,
              start_point,
              end_point,
              dims.diameter,
              overlap_start: false,
              overlap_end: false,
              cap_start: false,
              cap_end: false
            )
          end
        return false unless success

        if dims.round?
          add_round_pipe_stock_details(group, start_point, end_point, dims.diameter, product)
        else
          Geometry::Mesh.keep_edges_visible(group)
        end

        true
      rescue => error
        puts "MasterFlowGeometry.build_pipe failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      def build_stack_cap(group:, center:, axis:, product:, preferred_width_axis: nil, preferred_height_axis: nil)
        return false unless group && group.valid? && center && axis && product
        direction = normalized(axis)
        return false unless direction

        overall = product.overall || {}
        width = overall[:width].to_f > EPSILON ? overall[:width].to_f : product.width.to_f
        height = overall[:height].to_f > EPSILON ? overall[:height].to_f : product.height.to_f
        depth = overall[:depth].to_f > EPSILON ? overall[:depth].to_f : 0.60

        basis = Geometry::RectangularFrame.basis_for_axis(
          direction,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
        return false unless basis

        outer_face = center.offset(direction, depth)
        success = Geometry::RectangularPipeBuilder.build_into(
          group,
          center,
          outer_face,
          width,
          height,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: true,
          preferred_width_axis: basis[:width_axis],
          preferred_height_axis: basis[:height_axis],
          allow_relevel: false
        )
        Geometry::Mesh.keep_edges_visible(group) if success
        success
      rescue => error
        puts "MasterFlowGeometry.build_stack_cap failed: #{error.message}"
        false
      end

      def build_round_cap(group:, center:, axis:, product:)
        return false unless group && group.valid? && center && axis && product
        direction = normalized(axis)
        return false unless direction

        diameter = product.diameter.to_f
        return false if diameter <= EPSILON
        overall = product.overall || {}
        depth = overall[:depth].to_f
        depth = [diameter * 0.16, 0.55].max if depth <= EPSILON

        # The catalog cap is a shallow sheet-metal cup, not a decorative disk.
        # Build a short cylindrical skirt with a closed outside face and a crisp
        # open-end rim where it slips over the duct.
        outer = center.offset(direction, depth)
        success = Geometry::PipeBuilder.build_into(
          group,
          center,
          outer,
          diameter,
          overlap_start: false,
          overlap_end: false,
          cap_start: false,
          cap_end: true
        )
        return false unless success

        # PipeBuilder smooths cylindrical edges; add a visible installation rim.
        axis_a, axis_b = round_basis(direction)
        if axis_a && axis_b
          reveal_polyline_ring(group.entities, round_ring_points(center, axis_a, axis_b, diameter / 2.0))
          reveal_polyline_ring(group.entities, round_ring_points(outer, axis_a, axis_b, diameter / 2.0))
        end
        Geometry::Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "MasterFlowGeometry.build_round_cap failed: #{error.message}"
        false
      end

      def elbow_exit_point(start_point:, entry_vector:, exit_vector:, dimensions:, product:)
        entry = normalized(entry_vector)
        exitv = normalized(exit_vector)
        return nil unless entry && exitv
        return nil unless right_angle?(entry, exitv)

        radius = elbow_radius(product, dimensions)
        return nil unless radius > EPSILON

        start_point.offset(entry, radius).offset(exitv, radius)
      rescue
        nil
      end

      def build_elbow(group:, start_point:, entry_vector:, exit_vector:, dimensions:, product:, preferred_width_axis: nil, preferred_height_axis: nil)
        dims = Model::DuctDimensions.coerce(dimensions)
        entry = normalized(entry_vector)
        exitv = normalized(exit_vector)
        return nil unless group && group.valid? && entry && exitv && product
        return nil unless right_angle?(entry, exitv)

        dims.rectangular? ?
          build_rectangular_elbow(
            group: group,
            start_point: start_point,
            entry: entry,
            exitv: exitv,
            dimensions: dims,
            product: product,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          ) :
          build_round_adjustable_elbow(
            group: group,
            start_point: start_point,
            entry: entry,
            exitv: exitv,
            dimensions: dims,
            product: product
          )
      rescue => error
        puts "MasterFlowGeometry.build_elbow failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def build_round_tee(group:, center:, main_vector:, branch_vector:, diameter:, main_depth:, branch_depth:)
        main = normalized(main_vector)
        branch = normalized(branch_vector)
        return false unless main && branch

        diameter = diameter.to_f
        radius = diameter / 2.0
        left = center.offset(main.clone.reverse, main_depth.to_f)
        right = center.offset(main, main_depth.to_f)
        branch_end = center.offset(branch, branch_depth.to_f)

        # Master Flow's stocked tee is a straight barrel with a fabricated
        # perpendicular saddle.  Keep the main completely straight and flare the
        # branch only at the intersection instead of using the generic rounded
        # tee hub.
        Geometry::PipeBuilder.build_into(
          group, left, right, diameter,
          overlap_start: false, overlap_end: false,
          cap_start: false, cap_end: false
        )

        saddle_penetration = [diameter * 0.34, 0.45].max
        saddle_length = [diameter * 0.38, branch_depth.to_f * 0.45].min
        saddle_start = center.offset(branch.clone.reverse, saddle_penetration)
        saddle_end = center.offset(branch, saddle_length)

        build_round_frustum(
          group.entities,
          saddle_start,
          saddle_end,
          radius * 1.10,
          radius,
          visible_start_ring: false,
          visible_end_ring: false
        )

        if saddle_end.distance(branch_end) > EPSILON
          Geometry::PipeBuilder.build_into(
            group, saddle_end, branch_end, diameter,
            overlap_start: false, overlap_end: false,
            cap_start: false, cap_end: false
          )
        end

        finish_fabricated_round_fitting!(group)
        add_round_ring(group.entities, left, main, radius)
        add_round_ring(group.entities, right, main, radius)
        add_round_ring(group.entities, branch_end, branch, radius)
        add_round_bead(group.entities, left.offset(main, catalog_bead_offset(diameter)), main, radius)
        add_round_bead(group.entities, right.offset(main.clone.reverse, catalog_bead_offset(diameter)), main, radius)
        add_round_bead(group.entities, branch_end.offset(branch.clone.reverse, catalog_bead_offset(diameter)), branch, radius)
        add_round_seam(group.entities, left, right, main, radius)
        add_round_seam(group.entities, saddle_end, branch_end, branch, radius)
        add_crimp_marks(group.entities, right, main, radius, diameter)
        add_crimp_marks(group.entities, branch_end, branch, radius, diameter)
        Geometry::Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "MasterFlowGeometry.build_round_tee failed: #{error.message}"
        puts error.backtrace.join("\n") if error.backtrace
        false
      end

      # Returns the semantic socket layout for a stocked Master Flow lateral.
      # The catalog/retailer envelope dimensions are axis-aligned product-box
      # measurements, not a centerline drawing.  Use them as an envelope
      # constraint: the main remains a straight barrel, while the 45-degree
      # branch is tucked beside the forward half of that barrel rather than
      # projecting beyond it like a generic symmetric Y.
      def wye_layout(stem_point:, forward_vector:, side_axis:, product:)
        forward = normalized(forward_vector)
        side = Geometry::VectorMath.perpendicularized(side_axis, forward)
        return nil unless forward && side && product
        side.normalize!

        angle = (product.angle_degrees || 45.0).to_f * Math::PI / 180.0
        sin_angle = Math.sin(angle).abs
        cos_angle = Math.cos(angle).abs
        return nil if sin_angle <= EPSILON

        branch = vector_sum(
          scaled_vector(forward, Math.cos(angle)),
          scaled_vector(side, Math.sin(angle))
        )
        branch = normalized(branch)
        return nil unless branch

        inlet = product.diameter.to_f
        outlet = (product.outlet_diameter || product.branch_diameter || inlet).to_f
        inlet_radius = inlet / 2.0
        outlet_radius = outlet / 2.0
        overall = product.overall || {}

        envelope_a = overall[:height].to_f
        envelope_b = overall[:width].to_f
        published = [envelope_a, envelope_b].select { |value| value > EPSILON }

        main_span = published.max || [inlet * 2.5, outlet * 2.5].max
        lateral_span = published.min || [inlet * 1.9, outlet * 1.9].max
        lateral_span = [lateral_span, inlet_radius + outlet_radius * 1.8].max unless published.length >= 2

        # The far side of the main shell already consumes inlet_radius of the
        # published lateral envelope.  A circular branch mouth contributes only
        # outlet_radius*cos(angle) in the side direction.  Solving the remainder
        # for the branch center gives a stable 45-degree stocked-lateral layout.
        branch_center_side = lateral_span - inlet_radius - outlet_radius * cos_angle
        branch_center_side = [branch_center_side, outlet * 0.78].max
        branch_reach = branch_center_side / sin_angle

        # Keep the branch mouth inside the forward envelope.  This is the key
        # difference from the old implementation, which let the branch tip run
        # past the straight outlet and made the part read as a symmetric Y.
        branch_center_forward = main_span - outlet_radius * sin_angle
        branch_forward_component = branch_reach * cos_angle
        junction_distance = branch_center_forward - branch_forward_component
        min_junction = [inlet * 0.55, outlet * 0.55].max
        max_junction = main_span - [outlet * 1.05, inlet * 0.60].max
        junction_distance = [[junction_distance, min_junction].max, max_junction].min

        forward_socket = stem_point.offset(forward, main_span)
        junction = stem_point.offset(forward, junction_distance)
        branch_socket = junction.offset(branch, branch_reach)

        {
          stem_socket: stem_point,
          forward_socket: forward_socket,
          junction: junction,
          branch_socket: branch_socket,
          branch_axis: branch,
          main_span: main_span,
          lateral_span: lateral_span
        }
      rescue => error
        puts "MasterFlowGeometry.wye_layout failed: #{error.message}"
        nil
      end

      def build_round_wye(group:, layout:, product:)
        return false unless group && group.valid? && layout && product

        stem = layout[:stem_socket]
        forward_end = layout[:forward_socket]
        junction = layout[:junction]
        branch_end = layout[:branch_socket]
        main_axis = normalized(stem.vector_to(forward_end))
        branch_axis = normalized(junction.vector_to(branch_end))
        return false unless main_axis && branch_axis

        inlet = product.diameter.to_f
        outlet = (product.outlet_diameter || product.branch_diameter || inlet).to_f
        inlet_radius = inlet / 2.0
        outlet_radius = outlet / 2.0
        main_length = stem.distance(forward_end)
        branch_length = junction.distance(branch_end)

        # Stocked Master Flow wyes are fabricated laterals: one straight barrel
        # plus an angled takeoff.  Equal-size products keep the barrel cylindrical;
        # Y8X6X6/Y10X8X8 taper the barrel from the larger inlet to the smaller
        # straight outlet instead of grafting a separate reducer onto a generic Y.
        if (inlet - outlet).abs <= EPSILON
          Geometry::PipeBuilder.build_into(
            group, stem, forward_end, inlet,
            overlap_start: false, overlap_end: false,
            cap_start: false, cap_end: false
          )
        else
          build_round_frustum(
            group.entities,
            stem,
            forward_end,
            inlet_radius,
            outlet_radius,
            visible_start_ring: false,
            visible_end_ring: false
          )
        end

        # Build a true miter/saddle intersection instead of pushing a conical
        # branch through the main barrel.  The old overlap produced the visible
        # teardrop/bulge underneath the wye and the pinched white cusp at the
        # junction.  A stocked lateral is made by cutting the branch to the main
        # shell, so compute that cut curve directly on the barrel surface.
        junction_distance = stem.distance(junction)
        local_main_radius = radius_on_linear_taper(
          inlet_radius,
          outlet_radius,
          junction_distance,
          main_length
        )

        saddle = build_round_saddle_branch(
          entities: group.entities,
          junction: junction,
          branch_end: branch_end,
          main_axis: main_axis,
          main_radius: local_main_radius,
          branch_axis: branch_axis,
          branch_radius: outlet_radius
        )
        return false unless saddle
        neck_end = saddle[:neck_center]

        finish_fabricated_round_fitting!(group)

        # Crisp connection rims and sheet-metal bead/seam details.  The forward
        # and angled outlets are the crimped ends visible in the Master Flow
        # product family; the stem is left as the smooth receiving end.
        add_round_ring(group.entities, stem, main_axis, inlet_radius)
        add_round_ring(group.entities, forward_end, main_axis, outlet_radius)
        add_round_ring(group.entities, branch_end, branch_axis, outlet_radius)

        bead = catalog_bead_offset(outlet)
        inlet_bead = catalog_bead_offset(inlet)
        add_round_bead(group.entities, stem.offset(main_axis, inlet_bead), main_axis, radius_on_linear_taper(inlet_radius, outlet_radius, inlet_bead, main_length))
        add_round_bead(group.entities, forward_end.offset(main_axis.clone.reverse, bead), main_axis, radius_on_linear_taper(inlet_radius, outlet_radius, main_length - bead, main_length))
        add_round_bead(group.entities, branch_end.offset(branch_axis.clone.reverse, bead), branch_axis, outlet_radius)

        add_round_seam(group.entities, stem, forward_end, main_axis, [inlet_radius, outlet_radius])
        add_round_seam(group.entities, neck_end, branch_end, branch_axis, outlet_radius) if neck_end && neck_end.distance(branch_end) > EPSILON
        # The actual saddle cut is the attachment seam.  Showing this irregular
        # curve makes the branch read as a fabricated lateral instead of a blob.
        reveal_polyline_ring(group.entities, saddle[:saddle_ring])
        add_crimp_marks(group.entities, forward_end, main_axis, outlet_radius, outlet)
        add_crimp_marks(group.entities, branch_end, branch_axis, outlet_radius, outlet)

        Geometry::Mesh.apply_material_from_group(group)
        true
      rescue => error
        puts "MasterFlowGeometry.build_round_wye failed: #{error.message}"
        puts error.backtrace.join("\n")
        false
      end

      # Mesh a round branch whose inner edge is cut to the cylindrical main
      # barrel.  Each point around the branch circumference starts at the
      # positive intersection of that ray with the main cylinder.  This is the
      # geometric equivalent of the fish-mouth/saddle cut used on a fabricated
      # round lateral.
      def build_round_saddle_branch(entities:, junction:, branch_end:, main_axis:, main_radius:, branch_axis:, branch_radius:)
        main = normalized(main_axis)
        branch = normalized(branch_axis)
        return nil unless entities && junction && branch_end && main && branch

        main_radius = main_radius.to_f
        branch_radius = branch_radius.to_f
        return nil if main_radius <= EPSILON || branch_radius <= EPSILON

        branch_length = junction.distance(branch_end)
        return nil if branch_length <= EPSILON

        axis_a, axis_b = round_basis(branch)
        return nil unless axis_a && axis_b

        branch_parallel = scaled_vector(main, branch.dot(main))
        branch_perp = vector_sum(branch, scaled_vector(branch_parallel, -1.0))
        a = branch_perp.dot(branch_perp)
        return nil if a <= EPSILON

        saddle_ring = []
        saddle_t = []

        ROUND_SEGMENTS.times do |index|
          theta = Math::PI * 2.0 * index.to_f / ROUND_SEGMENTS.to_f
          radial = vector_sum(
            scaled_vector(axis_a, Math.cos(theta)),
            scaled_vector(axis_b, Math.sin(theta))
          )
          radial = normalized(radial)
          return nil unless radial

          offset = scaled_vector(radial, branch_radius)
          offset_parallel = scaled_vector(main, offset.dot(main))
          offset_perp = vector_sum(offset, scaled_vector(offset_parallel, -1.0))

          b = branch_perp.dot(offset_perp)
          c = offset_perp.dot(offset_perp) - main_radius * main_radius
          discriminant = b * b - a * c
          discriminant = 0.0 if discriminant < 0.0 && discriminant > -EPSILON
          return nil if discriminant < 0.0

          # a*t^2 + 2*b*t + c = 0.  The positive root is where the branch
          # leaves the main shell on its outward path.
          t = (-b + Math.sqrt(discriminant)) / a
          t = 0.0 if t < 0.0 && t > -EPSILON
          return nil if t < 0.0

          # The product envelope should always leave some branch neck outside
          # the main barrel.  Clamp only as a last-resort numerical guard so a
          # malformed catalog dimension cannot invert the mesh.
          t = [t, branch_length * 0.94].min
          center = junction.offset(branch, t)
          saddle_ring << center.offset(radial, branch_radius)
          saddle_t << t
        end

        max_t = saddle_t.max.to_f
        bead_clearance = [branch_radius * 0.18, 0.22].max
        desired_neck_t = max_t + [branch_radius * 0.16, 0.28].max
        max_neck_t = branch_length - bead_clearance
        neck_t = [desired_neck_t, max_neck_t].min

        if neck_t > max_t + 0.03
          neck_center = junction.offset(branch, neck_t)
          neck_ring = round_ring_points(neck_center, axis_a, axis_b, branch_radius)
          connect_round_rings(entities, saddle_ring, neck_ring)

          if neck_center.distance(branch_end) > EPSILON
            end_ring = round_ring_points(branch_end, axis_a, axis_b, branch_radius)
            connect_round_rings(entities, neck_ring, end_ring)
          end
        else
          neck_center = branch_end
          end_ring = round_ring_points(branch_end, axis_a, axis_b, branch_radius)
          connect_round_rings(entities, saddle_ring, end_ring)
        end

        {
          saddle_ring: saddle_ring,
          neck_center: neck_center,
          max_saddle_distance: max_t
        }
      rescue => error
        puts "MasterFlowGeometry.build_round_saddle_branch failed: #{error.message}"
        puts error.backtrace.join("\\n") if error.backtrace
        nil
      end
      private_class_method :build_round_saddle_branch

      def build_transition(group:, start_point:, end_point:, start_dimensions:, end_dimensions:, product:, preferred_width_axis: nil, preferred_height_axis: nil)
        start_dims = Model::DuctDimensions.coerce(start_dimensions)
        end_dims = Model::DuctDimensions.coerce(end_dimensions, fallback: start_dims)
        return false unless product

        if start_dims.round? && end_dims.round?
          build_catalog_round_reducer(
            group: group,
            start_point: start_point,
            end_point: end_point,
            start_diameter: start_dims.diameter,
            end_diameter: end_dims.diameter
          )
        elsif start_dims.shape != end_dims.shape
          # Stack boots have a visibly fabricated rectangular end and round
          # collar. The existing mixed builder is used for the tapered skin, then
          # catalog seam/collar details are added so it does not read as a generic
          # smooth morph.
          ok = Geometry::MixedTransitionBuilder.build_into(
            group,
            start_point,
            end_point,
            start_dimensions: start_dims,
            end_dimensions: end_dims,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )
          return false unless ok
          add_stack_boot_details(
            group: group,
            start_point: start_point,
            end_point: end_point,
            start_dimensions: start_dims,
            end_dimensions: end_dims,
            preferred_width_axis: preferred_width_axis,
            preferred_height_axis: preferred_height_axis
          )
          true
        else
          false
        end
      rescue => error
        puts "MasterFlowGeometry.build_transition failed: #{error.message}"
        false
      end

      def catalog_piece?(piece_or_group)
        group = piece_or_group.respond_to?(:group) ? piece_or_group.group : piece_or_group
        return false unless group && group.valid?
        !group.get_attribute(Catalog::Manager::DICTIONARY, "catalog_key").to_s.empty?
      rescue
        false
      end

      # ------------------------------------------------------------------------
      # Internal geometry helpers

      def build_round_adjustable_elbow(group:, start_point:, entry:, exitv:, dimensions:, product:)
        radius = elbow_radius(product, dimensions)
        normal = entry.cross(exitv)
        return nil if normal.length <= EPSILON
        normal.normalize!

        center_offset = normal.cross(entry)
        center_offset.normalize!
        center = start_point.offset(center_offset, radius)
        total_steps = ELBOW_GORE_COUNT * ELBOW_SUBDIVISIONS_PER_GORE
        angle = Math::PI / 2.0
        rings = []

        start_axis_a = normal.clone
        start_axis_b = entry.cross(start_axis_a)
        return nil if start_axis_b.length <= EPSILON
        start_axis_b.normalize!

        (total_steps + 1).times do |index|
          theta = angle * index.to_f / total_steps.to_f
          rotation = Geom::Transformation.rotation(center, normal, theta)
          ring_center = start_point.transform(rotation)
          axis_a = start_axis_a.transform(rotation)
          axis_b = start_axis_b.transform(rotation)
          axis_a.normalize!
          axis_b.normalize!
          rings << round_ring_points(ring_center, axis_a, axis_b, dimensions.diameter / 2.0)
        end

        entities = group.entities
        total_steps.times do |ring_index|
          connect_round_rings(entities, rings[ring_index], rings[ring_index + 1])
        end

        # Hide the dense mesh, then reveal the four characteristic adjustable
        # elbow gore/swivel boundaries plus both connection rings.
        entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?
          edge.hidden = true
          edge.soft = true if edge.respond_to?(:soft=)
          edge.smooth = true if edge.respond_to?(:smooth=)
        end

        boundary_indexes = (0..ELBOW_GORE_COUNT).map { |i| i * ELBOW_SUBDIVISIONS_PER_GORE }
        boundary_indexes.each { |idx| reveal_ring(entities, rings[idx]) }
        Geometry::Mesh.apply_material_from_group(group)

        end_point = start_point.offset(entry, radius).offset(exitv, radius)
        {
          end_point: end_point,
          start_basis: nil,
          end_basis: nil,
          bend_radius: radius
        }
      end
      private_class_method :build_round_adjustable_elbow

      def build_rectangular_elbow(group:, start_point:, entry:, exitv:, dimensions:, product:, preferred_width_axis:, preferred_height_axis:)
        radius = elbow_radius(product, dimensions)
        end_point = start_point.offset(entry, radius).offset(exitv, radius)
        turn = start_point.offset(entry, radius)

        start_basis = Geometry::RectangularFrame.stable_basis_for_axis(
          entry,
          dimensions.width,
          dimensions.height,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis,
          allow_relevel: false
        )
        return nil unless start_basis

        end_basis = Geometry::RectangularFrame.stable_transport_basis(
          from_axis: entry,
          to_axis: exitv,
          width_axis: start_basis[:width_axis],
          height_axis: start_basis[:height_axis],
          width: dimensions.width,
          height: dimensions.height,
          allow_relevel: false
        )
        return nil unless end_basis

        miter = [[dimensions.largest * 0.42, radius * 0.42].min, dimensions.largest * 0.18].max
        before = turn.offset(entry.clone.reverse, miter)
        after = turn.offset(exitv, miter)

        if start_point.distance(before) > EPSILON
          Geometry::RectangularPipeBuilder.build_into(
            group, start_point, before, dimensions.width, dimensions.height,
            overlap_start: false, overlap_end: false, cap_start: false, cap_end: false,
            preferred_width_axis: start_basis[:width_axis],
            preferred_height_axis: start_basis[:height_axis], allow_relevel: false
          )
        end

        if after.distance(end_point) > EPSILON
          Geometry::RectangularPipeBuilder.build_into(
            group, after, end_point, dimensions.width, dimensions.height,
            overlap_start: false, overlap_end: false, cap_start: false, cap_end: false,
            preferred_width_axis: end_basis[:width_axis],
            preferred_height_axis: end_basis[:height_axis], allow_relevel: false
          )
        end

        before_corners = Geometry::RectangularFrame.rectangle_corners_from_basis(
          before, start_basis[:width_axis], start_basis[:height_axis], dimensions.width, dimensions.height
        )
        after_corners = Geometry::RectangularFrame.rectangle_corners_from_basis(
          after, end_basis[:width_axis], end_basis[:height_axis], dimensions.width, dimensions.height
        )
        return nil unless before_corners.length == 4 && after_corners.length == 4

        4.times do |i|
          j = (i + 1) % 4
          Geometry::Mesh.add_quad(group.entities, before_corners[i], before_corners[j], after_corners[j], after_corners[i])
        end

        # Two crisp transverse seams make the fixed miter construction obvious.
        reveal_polyline_ring(group.entities, before_corners)
        reveal_polyline_ring(group.entities, after_corners)
        Geometry::Mesh.keep_edges_visible(group)
        Geometry::Mesh.apply_material_from_group(group)

        {
          end_point: end_point,
          start_basis: start_basis,
          end_basis: end_basis,
          bend_radius: radius
        }
      end
      private_class_method :build_rectangular_elbow

      def build_catalog_round_reducer(group:, start_point:, end_point:, start_diameter:, end_diameter:)
        direction = normalized(start_point.vector_to(end_point))
        return false unless direction
        total = start_point.distance(end_point)
        return false if total <= EPSILON

        collar = [[total * 0.16, [start_diameter, end_diameter].min * 0.22].min, total * 0.28].min
        collar = 0.0 if collar < 0.05
        taper_start = start_point.offset(direction, collar)
        taper_end = end_point.offset(direction.clone.reverse, collar)

        build_round_frustum(group.entities, start_point, taper_start, start_diameter / 2.0, start_diameter / 2.0, visible_start_ring: true, visible_end_ring: true) if collar > EPSILON
        build_round_frustum(group.entities, taper_start, taper_end, start_diameter / 2.0, end_diameter / 2.0, visible_start_ring: false, visible_end_ring: false)
        build_round_frustum(group.entities, taper_end, end_point, end_diameter / 2.0, end_diameter / 2.0, visible_start_ring: true, visible_end_ring: true) if collar > EPSILON
        Geometry::Mesh.apply_material_from_group(group)
        true
      end
      private_class_method :build_catalog_round_reducer

      def build_round_frustum(entities, start_point, end_point, start_radius, end_radius, visible_start_ring:, visible_end_ring:)
        direction = normalized(start_point.vector_to(end_point))
        return false unless direction
        axis_a, axis_b = round_basis(direction)
        return false unless axis_a && axis_b

        start_ring = round_ring_points(start_point, axis_a, axis_b, start_radius)
        end_ring = round_ring_points(end_point, axis_a, axis_b, end_radius)
        connect_round_rings(entities, start_ring, end_ring)
        reveal_ring(entities, start_ring) if visible_start_ring
        reveal_ring(entities, end_ring) if visible_end_ring
        true
      end
      private_class_method :build_round_frustum

      def add_round_pipe_stock_details(group, start_point, end_point, diameter, product)
        direction = normalized(start_point.vector_to(end_point))
        return unless direction
        axis_a, axis_b = round_basis(direction)
        return unless axis_a && axis_b
        radius = diameter.to_f / 2.0
        length = start_point.distance(end_point)

        # Longitudinal snap-lock seam.
        seam_start = start_point.offset(axis_a, radius)
        seam_end = end_point.offset(axis_a, radius)
        visible_line(group.entities, seam_start, seam_end)

        # Beaded products receive two shallow bead rings near the ends. Standard
        # snap-lock pipe gets a single stop-bead near the crimped end.
        offsets =
          if product && product.style == :beaded
            [0.55, [length - 0.55, 0.55].max]
          else
            [[length - 0.45, length * 0.82].min]
          end
        offsets.each do |offset|
          next unless offset > 0.05 && offset < length - 0.05
          center = start_point.offset(direction, offset)
          ring = round_ring_points(center, axis_a, axis_b, radius * 1.012)
          reveal_ring(group.entities, ring)
        end
      rescue => error
        puts "MasterFlowGeometry.add_round_pipe_stock_details failed: #{error.message}"
      end
      private_class_method :add_round_pipe_stock_details

      def add_stack_boot_details(group:, start_point:, end_point:, start_dimensions:, end_dimensions:, preferred_width_axis:, preferred_height_axis:)
        vector = normalized(start_point.vector_to(end_point))
        return unless vector
        round_point = start_dimensions.round? ? start_point : end_point
        round_dims = start_dimensions.round? ? start_dimensions : end_dimensions
        rect_point = start_dimensions.rectangular? ? start_point : end_point
        rect_dims = start_dimensions.rectangular? ? start_dimensions : end_dimensions

        axis_a, axis_b = round_basis(vector)
        add_round_ring(group.entities, round_point, vector, round_dims.diameter / 2.0) if axis_a && axis_b

        basis = Geometry::RectangularFrame.basis_for_axis(
          vector,
          preferred_width_axis: preferred_width_axis,
          preferred_height_axis: preferred_height_axis
        )
        if basis
          corners = Geometry::RectangularFrame.rectangle_corners_from_basis(
            rect_point, basis[:width_axis], basis[:height_axis], rect_dims.width, rect_dims.height
          )
          reveal_polyline_ring(group.entities, corners) if corners.length == 4
        end
      end
      private_class_method :add_stack_boot_details

      # Hide construction tessellation for fabricated round catalog parts. The
      # visible seams/rims are re-added explicitly after all overlapping shells
      # have been created so the result reads as sheet metal, not a triangulated
      # procedural surface.
      def finish_fabricated_round_fitting!(group)
        return unless group && group.valid?

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?
          edge.hidden = true
          edge.soft = true if edge.respond_to?(:soft=)
          edge.smooth = true if edge.respond_to?(:smooth=)
        end
      rescue => error
        puts "MasterFlowGeometry.finish_fabricated_round_fitting! failed: #{error.message}"
      end
      private_class_method :finish_fabricated_round_fitting!

      def catalog_bead_offset(diameter)
        [[diameter.to_f * 0.12, 0.42].max, 0.90].min
      rescue
        0.55
      end
      private_class_method :catalog_bead_offset

      def add_round_bead(entities, center, direction, radius)
        axis_a, axis_b = round_basis(direction)
        return unless axis_a && axis_b
        reveal_ring(entities, round_ring_points(center, axis_a, axis_b, radius.to_f * 1.012))
      rescue => error
        puts "MasterFlowGeometry.add_round_bead failed: #{error.message}"
      end
      private_class_method :add_round_bead

      def add_round_seam(entities, start_point, end_point, direction, radius)
        axis_a, = round_basis(direction)
        return unless axis_a

        start_radius, end_radius =
          if radius.is_a?(Array)
            [radius[0].to_f, radius[1].to_f]
          else
            [radius.to_f, radius.to_f]
          end

        visible_line(
          entities,
          start_point.offset(axis_a, start_radius * 1.002),
          end_point.offset(axis_a, end_radius * 1.002)
        )
      rescue => error
        puts "MasterFlowGeometry.add_round_seam failed: #{error.message}"
      end
      private_class_method :add_round_seam

      def add_branch_attachment_seam(entities, junction, branch_axis, radius)
        # A shallow raised ring just outside the barrel suggests the rolled/saddle
        # seam visible where a Master Flow lateral is joined to the main shell.
        center = junction.offset(branch_axis, [radius.to_f * 0.34, 0.30].max)
        add_round_bead(entities, center, branch_axis, radius.to_f * 1.03)
      rescue => error
        puts "MasterFlowGeometry.add_branch_attachment_seam failed: #{error.message}"
      end
      private_class_method :add_branch_attachment_seam

      def add_crimp_marks(entities, outlet_center, outward_axis, radius, diameter)
        axis = normalized(outward_axis)
        axis_a, axis_b = round_basis(axis)
        return unless axis && axis_a && axis_b

        length = [[diameter.to_f * 0.16, 0.48].max, 1.15].min
        inner_center = outlet_center.offset(axis.clone.reverse, length)
        mark_count = 12

        mark_count.times do |index|
          theta = Math::PI * 2.0 * index.to_f / mark_count.to_f
          radial = Geom::Vector3d.new(
            axis_a.x * Math.cos(theta) + axis_b.x * Math.sin(theta),
            axis_a.y * Math.cos(theta) + axis_b.y * Math.sin(theta),
            axis_a.z * Math.cos(theta) + axis_b.z * Math.sin(theta)
          )
          radial.normalize!

          outer = outlet_center.offset(radial, radius.to_f * 1.006)
          inner = inner_center.offset(radial, radius.to_f * 0.965)
          visible_line(entities, inner, outer)
        end
      rescue => error
        puts "MasterFlowGeometry.add_crimp_marks failed: #{error.message}"
      end
      private_class_method :add_crimp_marks

      def radius_on_linear_taper(start_radius, end_radius, distance, total_length)
        total = total_length.to_f
        return end_radius.to_f if total <= EPSILON
        t = [[distance.to_f / total, 0.0].max, 1.0].min
        start_radius.to_f + (end_radius.to_f - start_radius.to_f) * t
      rescue
        end_radius.to_f
      end
      private_class_method :radius_on_linear_taper

      def elbow_radius(product, dimensions)
        dims = Model::DuctDimensions.coerce(dimensions)
        overall = product && product.overall || {}
        if dims.round?
          radius = overall[:derived_centerline_radius].to_f
          return radius if radius > EPSILON
          return dims.diameter * 1.15
        end

        if product && product.style == :long_way_miter
          outside = overall[:height].to_f
          radius = outside - dims.width / 2.0
        else
          outside = overall[:height].to_f
          radius = outside - dims.height / 2.0
        end
        radius > EPSILON ? radius : dims.largest * 0.75
      rescue
        Model::DuctDimensions.coerce(dimensions).largest * 0.75
      end

      def right_angle?(a, b)
        (a.dot(b)).abs <= 0.02
      rescue
        false
      end

      def round_basis(direction)
        direction = normalized(direction)
        return nil unless direction
        reference = Geometry::RectangularFrame.best_reference_axis(direction)
        axis_a = direction.cross(reference)
        return nil if axis_a.length <= EPSILON
        axis_a.normalize!
        axis_b = direction.cross(axis_a)
        return nil if axis_b.length <= EPSILON
        axis_b.normalize!
        [axis_a, axis_b]
      end
      private_class_method :round_basis

      def round_ring_points(center, axis_a, axis_b, radius)
        Array.new(ROUND_SEGMENTS) do |i|
          angle = Math::PI * 2.0 * i.to_f / ROUND_SEGMENTS.to_f
          radial = Geom::Vector3d.new(
            axis_a.x * Math.cos(angle) + axis_b.x * Math.sin(angle),
            axis_a.y * Math.cos(angle) + axis_b.y * Math.sin(angle),
            axis_a.z * Math.cos(angle) + axis_b.z * Math.sin(angle)
          )
          radial.normalize!
          center.offset(radial, radius.to_f)
        end
      end
      private_class_method :round_ring_points

      def connect_round_rings(entities, a, b)
        ROUND_SEGMENTS.times do |i|
          j = (i + 1) % ROUND_SEGMENTS
          Geometry::Mesh.add_quad(entities, a[i], a[j], b[j], b[i])
        end
      end
      private_class_method :connect_round_rings

      def reveal_ring(entities, ring)
        ring.length.times do |i|
          visible_line(entities, ring[i], ring[(i + 1) % ring.length])
        end
      end
      private_class_method :reveal_ring

      def add_round_ring(entities, center, direction, radius)
        axis_a, axis_b = round_basis(direction)
        return unless axis_a && axis_b
        reveal_ring(entities, round_ring_points(center, axis_a, axis_b, radius))
      end
      private_class_method :add_round_ring

      def reveal_polyline_ring(entities, points)
        points.length.times do |i|
          visible_line(entities, points[i], points[(i + 1) % points.length])
        end
      end
      private_class_method :reveal_polyline_ring

      def visible_line(entities, a, b)
        edge = entities.add_line(a, b)
        return unless edge
        edge.hidden = false
        edge.soft = false if edge.respond_to?(:soft=)
        edge.smooth = false if edge.respond_to?(:smooth=)
        edge
      rescue
        nil
      end
      private_class_method :visible_line

      def normalized(vector)
        Geometry::VectorMath.normalized(vector, epsilon: EPSILON)
      end
      private_class_method :normalized

      def scaled_vector(vector, amount)
        Geom::Vector3d.new(vector.x * amount, vector.y * amount, vector.z * amount)
      end
      private_class_method :scaled_vector

      def vector_sum(a, b)
        Geom::Vector3d.new(a.x + b.x, a.y + b.y, a.z + b.z)
      end
      private_class_method :vector_sum
    end
  end
end


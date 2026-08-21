module DuctExtension
  module Geometry
    module Mesh
      EPSILON = 0.000001
      QUAD_PLANAR_TOLERANCE = 0.00001

      def self.add_face_safe(entities, points, reverse_if_normal_against: nil, log_errors: true)
        clean_points = sanitize_face_points(points)
        return nil if clean_points.length < 3
        return nil if duplicate_face_point?(clean_points)

        face = entities.add_face(clean_points)
        return nil unless face

        if reverse_if_normal_against
          normal = normalized(reverse_if_normal_against)

          if normal && face.normal.dot(normal) < 0
            face.reverse!
          end
        end

        face
      rescue => error
        puts "Mesh.add_face_safe failed: #{error.message}" if log_errors
        nil
      end


      def self.sanitize_face_points(points)
        result = []

        Array(points).compact.each do |point|
          next if !result.empty? && same_point?(result.last, point)
          result << point
        end

        result.pop if result.length > 1 && same_point?(result.first, result.last)
        result
      end

      def self.duplicate_face_point?(points)
        points.each_with_index do |point, index|
          ((index + 1)...points.length).each do |other_index|
            return true if same_point?(point, points[other_index])
          end
        end

        false
      end

      def self.same_point?(point_a, point_b)
        point_a.distance(point_b) <= EPSILON
      rescue
        point_a == point_b
      end

      def self.add_quad(entities, p1, p2, p3, p4)
        points = sanitize_face_points([p1, p2, p3, p4])
        return nil unless points.length == 4
        return nil if duplicate_face_point?(points)

        # Curved round surfaces are built between neighboring polygon rings.
        # Their four corner points are often mathematically non-planar, so
        # asking SketchUp to add them as a quad first generates an exception
        # for every panel before the old fallback can run.  Avoid that hot
        # exception path: only try a quad when the points are planar enough.
        if quad_planar?(points)
          face = add_face_safe(entities, points, log_errors: false)
          return face if face
        end

        # Triangles are always planar. This is the intended representation for
        # a ruled panel that twists between two circular rings. Round builders
        # soft/smooth these edges afterward, so the diagonal is not visible.
        first = add_face_safe(entities, [points[0], points[1], points[2]])
        second = add_face_safe(entities, [points[0], points[2], points[3]])
        first || second
      end

      def self.quad_planar?(points, tolerance: QUAD_PLANAR_TOLERANCE)
        return false unless points && points.length == 4

        origin = points[0]
        edge_a = origin.vector_to(points[1])
        edge_b = origin.vector_to(points[2])
        normal = edge_a.cross(edge_b)
        return false if normal.length <= EPSILON

        normal.normalize!
        distance = origin.vector_to(points[3]).dot(normal).abs
        distance <= tolerance.to_f
      rescue
        false
      end

      def self.soft_smooth_edges(group)
        return unless group && group.valid?

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.soft = true
          edge.smooth = true
        end
      rescue => error
        puts "Mesh.soft_smooth_edges failed: #{error.message}"
      end

      def self.soft_smooth_round_edges(group)
        soft_smooth_edges(group)
      end

      def self.keep_edges_visible(group)
        return unless group && group.valid?

        group.entities.grep(Sketchup::Edge).each do |edge|
          next unless edge.valid?

          edge.hidden = false
        end
      rescue => error
        puts "Mesh.keep_edges_visible failed: #{error.message}"
      end

      def self.apply_material_from_group(group)
        return unless group && group.valid?
        return unless group.material

        material = group.material

        group.entities.grep(Sketchup::Face).each do |face|
          next unless face.valid?

          face.material = material
          face.back_material = material
        end
      rescue => error
        puts "Mesh.apply_material_from_group failed: #{error.message}"
      end

      def self.normalized(vector)
        VectorMath.normalized(vector, epsilon: EPSILON)
      end
    end
  end
end


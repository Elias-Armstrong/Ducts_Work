module DuctExtension
  module Services
    # Owns the temporary closure faces placed on open fitting ports.
    # Older versions called these "tee caps", but crosses and wyes use the same
    # mechanism, so the behavior belongs in one fitting-agnostic service.
    module PortCapService
      DICTIONARY = "DuctExtension"
      CAP_SEGMENTS = 32
      CONNECTION_TOLERANCE_FACTOR = 4.0

      module_function

      def add(group, port)
        return false unless group && group.valid? && port

        port.rectangular? ? add_rectangular(group, port) : add_round(group, port)
        true
      rescue => error
        puts "PortCapService.add failed: #{error.message}"
        false
      end

      def remove(port)
        return false unless port && port.piece

        group = port.piece.group
        return false unless group && group.valid?

        removed = false
        group.entities.grep(Sketchup::Face).each do |face|
          next unless face.valid?
          next unless cap_face?(face)

          cap_point = face.get_attribute(DICTIONARY, "cap_point")
          next unless cap_point

          point = Geom::Point3d.new(cap_point)
          next unless point.distance(port.point) < Model::Network::CONNECTION_DISTANCE * CONNECTION_TOLERANCE_FACTOR

          boundary_edges = face.edges.to_a
          face.erase!
          hide_surviving_boundary_edges(boundary_edges)
          removed = true
        end
        removed
      rescue => error
        puts "PortCapService.remove failed: #{error.message}"
        false
      end

      def add_round(group, port)
        normal = Geometry::VectorMath.normalized(port.vector)
        return unless normal

        circle = group.entities.add_circle(
          port.point,
          normal,
          port.diameter.to_f / 2.0,
          CAP_SEGMENTS
        )

        face = group.entities.add_face(circle)
        tag_cap(face, port, normal)
      end
      private_class_method :add_round

      def add_rectangular(group, port)
        normal = Geometry::VectorMath.normalized(port.vector)
        return unless normal

        corners = Geometry::RectangularFrame.rectangle_corners(
          port.point,
          normal,
          port.width,
          port.height,
          preferred_width_axis: port.width_axis,
          preferred_height_axis: port.height_axis
        )
        return if corners.empty?

        face = group.entities.add_face(corners)
        tag_cap(face, port, normal)
      end
      private_class_method :add_rectangular

      def tag_cap(face, port, normal)
        return unless face

        face.reverse! if face.normal.dot(normal) < 0
        face.set_attribute(DICTIONARY, "duct_cap", true)
        face.set_attribute(DICTIONARY, "tee_cap", true) # legacy compatibility
        face.set_attribute(DICTIONARY, "cap_point", port.point.to_a)
        face.edges.each { |edge| edge.hidden = false if edge.valid? }
      end
      private_class_method :tag_cap

      # A removed cap can share its perimeter with the fitting body. Erasing only
      # the face leaves that ring/rectangle visible at the new connection. Keep
      # shared geometry intact, but hide the surviving cap boundary edges.
      def hide_surviving_boundary_edges(edges)
        Array(edges).each do |edge|
          next unless edge && edge.valid?

          edge.hidden = true
        end
      end
      private_class_method :hide_surviving_boundary_edges

      def cap_face?(face)
        face.get_attribute(DICTIONARY, "duct_cap") || face.get_attribute(DICTIONARY, "tee_cap")
      end
      private_class_method :cap_face?
    end
  end
end

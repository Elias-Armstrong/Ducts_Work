module DuctExtension
  module Catalog
    module Manager
      DICTIONARY = "DuctExtensionCatalog"
      ACTIVE_KEY = "active_catalog"
      BASE_KEY = :base
      MASTER_FLOW_KEY = :master_flow
      IMPERIAL_KEY = :imperial
      TOLERANCE = 0.01

      module_function

      def catalog_module_for(key)
        case key.to_sym
        when MASTER_FLOW_KEY then MasterFlow
        when IMPERIAL_KEY then Imperial
        else nil
        end
      rescue
        nil
      end

      def active_key(model = nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        return BASE_KEY unless model

        text = model.get_attribute(DICTIONARY, ACTIVE_KEY, BASE_KEY.to_s).to_s
        case text
        when MASTER_FLOW_KEY.to_s then MASTER_FLOW_KEY
        when IMPERIAL_KEY.to_s then IMPERIAL_KEY
        else BASE_KEY
        end
      rescue
        BASE_KEY
      end

      def active?(model = nil)
        active_key(model) != BASE_KEY
      end

      def active_catalog(model = nil)
        catalog_module_for(active_key(model))
      end

      def active_name(model = nil)
        catalog = active_catalog(model)
        catalog ? catalog::NAME : "Base / Generic"
      rescue
        "Base / Generic"
      end

      def set_active(model, key)
        return false unless model

        text = key.to_s.downcase
        normalized =
          if text.include?("imperial")
            IMPERIAL_KEY
          elsif text.include?("master")
            MASTER_FLOW_KEY
          else
            BASE_KEY
          end
        model.set_attribute(DICTIONARY, ACTIVE_KEY, normalized.to_s)
        normalized
      rescue => error
        puts "Catalog::Manager.set_active failed: #{error.message}"
        false
      end

      def prompt_set_catalog(model = nil)
        model ||= Sketchup.active_model
        current = active_name(model)

        input = ::UI.inputbox(
          ["Catalog:"],
          [current],
          ["Base / Generic|Master Flow|Imperial"],
          "Set Duct Catalog"
        )
        return nil unless input

        key = set_active(model, input[0])
        return nil unless key

        message =
          if key == BASE_KEY
            "Catalog cleared. New pieces will use the extension's base/generic geometry and free-form sizes."
          else
            "#{active_name(model)} catalog enabled. New duct pieces will be restricted to supported #{active_name(model)} products."
          end

        Sketchup.status_text = message if defined?(Sketchup)
        ::UI.messagebox(message)
        key
      rescue => error
        puts "Catalog::Manager.prompt_set_catalog failed: #{error.message}"
        nil
      end

      def all_products(model = nil)
        catalog = active_catalog(model)
        catalog ? catalog.products : []
      rescue
        []
      end

      def product_catalog_name(product, model = nil)
        if product && product.respond_to?(:catalog_name) && !product.catalog_name.to_s.empty?
          product.catalog_name.to_s
        else
          active_name(model)
        end
      rescue
        active_name(model)
      end

      def product_catalog_key(product, model = nil)
        if product && product.respond_to?(:catalog_key) && product.catalog_key
          product.catalog_key.to_sym
        else
          active_key(model)
        end
      rescue
        active_key(model)
      end

      def product_catalog_document(product, model = nil)
        if product && product.respond_to?(:catalog_document) && !product.catalog_document.to_s.empty?
          product.catalog_document.to_s
        else
          catalog = active_catalog(model)
          catalog ? catalog::CATALOG_DOCUMENT : ""
        end
      rescue
        ""
      end

      def product_by_sku(sku, model = nil)
        return nil if sku.to_s.empty?
        all_products(model).find { |product| product.sku.to_s == sku.to_s }
      end

      def pipe_products(shape, model = nil)
        return [] unless active?(model)
        wanted = shape.to_sym
        all_products(model).select { |p| p.family == :pipe && p.shape.to_sym == wanted }
      rescue
        []
      end

      def pipe_product(dimensions, model = nil)
        return nil unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)

        matches = pipe_products(dims.shape, model).select do |product|
          if dims.round?
            close?(product.diameter, dims.diameter)
          else
            rectangular_size_match?(product.width, product.height, dims.width, dims.height)
          end
        end
        return nil if matches.empty?

        if model
          saved = model.get_attribute(DICTIONARY, "pipe_#{dimensions_signature(dims)}").to_s
          preferred = matches.find { |product| product.sku.to_s == saved }
          return preferred if preferred
        end

        matches.first
      rescue
        nil
      end

      def save_pipe_preference(model, dimensions, product)
        return unless model && product
        model.set_attribute(DICTIONARY, "pipe_#{dimensions_signature(dimensions)}", product.sku)
      rescue => error
        puts "Catalog::Manager.save_pipe_preference failed: #{error.message}"
      end

      def elbow_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)

        all_products(model).select do |product|
          next false unless product.family == :elbow

          if dims.round?
            product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
          else
            product.shape.to_sym == :rectangular && rectangular_size_match?(
              product.width, product.height, dims.width, dims.height
            )
          end
        end
      rescue
        []
      end

      def preferred_elbow(model, dimensions)
        products = elbow_products(dimensions, model)
        return nil if products.empty?

        signature = dimensions_signature(dimensions)
        saved = model.get_attribute(DICTIONARY, "elbow_#{signature}").to_s
        products.find { |p| p.sku == saved } || products.first
      rescue
        elbow_products(dimensions, model).first
      end

      def elbow_for_angle(model, dimensions, angle)
        products = elbow_products(dimensions, model)
        return nil if products.empty?

        preferred = preferred_elbow(model, dimensions)
        return preferred if preferred && elbow_angle_supported?(preferred, dimensions, angle)

        # When a catalog has separate fixed 45°/90° rectangular products, keep
        # the user's preferred construction style (flat/side) where possible.
        if preferred
          same_style = products.find do |product|
            product.style == preferred.style && elbow_angle_supported?(product, dimensions, angle)
          end
          return same_style if same_style
        end

        products.find { |product| elbow_angle_supported?(product, dimensions, angle) }
      rescue
        nil
      end

      def save_elbow_preference(model, dimensions, product)
        return unless model && product
        model.set_attribute(DICTIONARY, "elbow_#{dimensions_signature(dimensions)}", product.sku)
      rescue => error
        puts "Catalog::Manager.save_elbow_preference failed: #{error.message}"
      end

      def junction_products(dimensions, family, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        return [] unless dims.round?

        all_products(model).select do |product|
          product.family == family.to_sym && close?(product.diameter, dims.diameter)
        end
      rescue
        []
      end

      def preferred_junction(model, dimensions, family)
        products = junction_products(dimensions, family, model)
        return nil if products.empty?

        signature = dimensions_signature(dimensions)
        saved = model && model.get_attribute(DICTIONARY, "#{family}_#{signature}").to_s
        products.find { |product| product.sku.to_s == saved.to_s } || products.first
      rescue
        junction_products(dimensions, family, model).first
      end

      def save_junction_preference(model, dimensions, family, product)
        return unless model && product
        model.set_attribute(DICTIONARY, "#{family}_#{dimensions_signature(dimensions)}", product.sku)
      rescue => error
        puts "Catalog::Manager.save_junction_preference failed: #{error.message}"
      end

      def tee_product(dimensions, model = nil)
        preferred_junction(model, dimensions, :tee)
      end

      def wye_product(dimensions, model = nil)
        preferred_junction(model, dimensions, :wye)
      end

      def transition_product(source_dimensions, target_dimensions, model = nil)
        return nil unless active?(model)
        source = Model::DuctDimensions.coerce(source_dimensions)
        target = Model::DuctDimensions.coerce(target_dimensions, fallback: source)
        return nil if source.same_size?(target, tolerance: TOLERANCE) && source.shape == target.shape

        if source.round? && target.round?
          large = [source.diameter, target.diameter].max
          small = [source.diameter, target.diameter].min

          return all_products(model).find do |product|
            product.family == :transition && product.shape.to_sym == :round &&
              close?(product.diameter, large) && close?(product.branch_diameter, small)
          end
        end

        if source.shape != target.shape
          rectangular = source.rectangular? ? source : target
          round = source.round? ? source : target

          return all_products(model).find do |product|
            product.family == :transition && product.shape.to_sym == :mixed &&
              rectangular_size_match?(product.width, product.height, rectangular.width, rectangular.height) &&
              close?(product.diameter, round.diameter)
          end
        end

        nil
      rescue
        nil
      end

      def transition_targets(source_dimensions, model = nil)
        return [] unless active?(model)
        source = Model::DuctDimensions.coerce(source_dimensions)
        results = []

        all_products(model).each do |product|
          next unless product.family == :transition

          if product.shape.to_sym == :round && source.round?
            if close?(source.diameter, product.diameter)
              results << Model::DuctDimensions.round(diameter: product.branch_diameter)
            elsif close?(source.diameter, product.branch_diameter)
              results << Model::DuctDimensions.round(diameter: product.diameter)
            end
          elsif product.shape.to_sym == :mixed
            rect_matches = source.rectangular? && rectangular_size_match?(
              product.width, product.height, source.width, source.height
            )
            round_matches = source.round? && close?(product.diameter, source.diameter)

            if rect_matches
              results << Model::DuctDimensions.round(diameter: product.diameter)
            elsif round_matches
              results << Model::DuctDimensions.rectangular(width: product.width, height: product.height)
            end
          end
        end

        unique_dimensions(results)
      rescue
        []
      end

      def allowed_branch_targets(main_dimensions, family:, model: nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        return [] unless active?(model)

        main = Model::DuctDimensions.coerce(main_dimensions)
        base_product = family.to_sym == :wye ? wye_product(main, model) : tee_product(main, model)
        return [] unless base_product

        [main] + transition_targets(main, model)
      rescue
        []
      end


      def product_for_piece_type(type, dimensions, model = nil)
        case type.to_sym
        when :pipe
          pipe_product(dimensions, model)
        when :elbow
          preferred_elbow(model || Sketchup.active_model, dimensions)
        when :tee
          tee_product(dimensions, model)
        when :wye
          wye_product(dimensions, model)
        else
          nil
        end
      rescue
        nil
      end

      def resize_piece_supported?(type, dimensions, model = nil)
        return true unless active?(model)
        !!product_for_piece_type(type, dimensions, model)
      end

      def end_cover_product(dimensions, model = nil)
        return nil unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        return nil unless dims.rectangular?

        all_products(model).find do |product|
          product.family == :end_cover && rectangular_size_match?(
            product.width, product.height, dims.width, dims.height
          )
        end
      rescue
        nil
      end

      def supported_cross?(_dimensions, model = nil)
        !active?(model)
      end

      def elbow_bend_radius(product, dimensions, fallback, angle: nil)
        return fallback.to_f unless product
        if defined?(MasterFlowGeometry) && MasterFlowGeometry.respond_to?(:elbow_radius)
          value = MasterFlowGeometry.elbow_radius(product, dimensions, angle: angle).to_f
          return value if value > 0.0
        end
        fallback.to_f
      rescue
        fallback.to_f
      end

      def elbow_angle_supported?(product, dimensions, angle)
        return true unless active?(Sketchup.active_model)
        return false unless product
        return MasterFlowGeometry.elbow_angle_supported?(product, dimensions, angle) if defined?(MasterFlowGeometry)
        false
      rescue
        false
      end

      def elbow_angle_status(product, dimensions, angle)
        dims = Model::DuctDimensions.coerce(dimensions)
        degrees = angle.to_f * 180.0 / Math::PI
        if dims.round? && product && product.style == :four_gore_adjustable
          "#{product_catalog_name(product)} #{product.sku}: adjustable round elbows support modeled turns through 90°; nearly straight directions use straight duct. Requested #{degrees.round(1)}°."
        else
          "#{product_catalog_name(product)} #{product && product.sku}: this catalog elbow is fixed at #{(product && product.angle_degrees || 90).to_f.round(1)}°. Requested #{degrees.round(1)}°."
        end
      rescue
        "Requested catalog elbow angle is not supported."
      end

      def transition_length(product, fallback)
        return fallback.to_f unless product
        value = product.transition_length.to_f
        value > 0.0 ? value : fallback.to_f
      rescue
        fallback.to_f
      end

      # For a catalog round tee, Home Depot's published assembled dimensions map
      # cleanly to the procedural tee axes:
      #   overall length = end-to-end main run
      #   overall height = branch tip to the opposite outside of the main tube
      #   overall width  = tube diameter
      # This lets us place semantic ports at the real catalog envelope instead of
      # using the generic 0.82D socket rule.
      def tee_main_socket_depth(product, fallback)
        return fallback.to_f unless product && product.overall
        length = product.overall[:length].to_f
        length > 0.0 ? length / 2.0 : fallback.to_f
      rescue
        fallback.to_f
      end

      def tee_branch_socket_depth(product, dimensions, fallback)
        return fallback.to_f unless product && product.overall
        dims = Model::DuctDimensions.coerce(dimensions)
        return fallback.to_f unless dims.round?

        overall_height = product.overall[:height].to_f
        depth = overall_height - dims.diameter.to_f / 2.0
        depth > 0.0 ? depth : fallback.to_f
      rescue
        fallback.to_f
      end

      def prompt_duct_settings(
        model:,
        current_shape:,
        current_diameter:,
        current_width:,
        current_height:,
        current_increment:
      )
        shape_input = ::UI.inputbox(
          ["Duct Shape:"],
          [current_shape.to_sym == :rectangular ? "Rectangular" : "Round"],
          ["Round|Rectangular"],
          "#{active_name(model)} Duct Settings"
        )
        return nil unless shape_input

        shape = shape_input[0].to_s.downcase.start_with?("rect") ? :rectangular : :round
        products = pipe_products(shape, model)
        if products.empty?
          ::UI.messagebox("No Master Flow #{shape} straight-duct product in the loaded catalog matches this selection.")
          return nil
        end

        current_dims =
          if shape == :round
            Model::DuctDimensions.round(diameter: current_diameter)
          else
            Model::DuctDimensions.rectangular(width: current_width, height: current_height)
          end

        selected = pipe_product(current_dims, model) || products.first
        labels = products.map(&:label)
        product_input = ::UI.inputbox(
          ["Duct Product:"],
          [selected.label],
          [labels.join("|")],
          "#{active_name(model)} Duct Product"
        )
        return nil unless product_input

        selected = products.find { |p| p.label == product_input[0].to_s } || selected
        dimensions = dimensions_for_pipe_product(selected)
        save_pipe_preference(model, dimensions, selected)
        elbows = elbow_products(dimensions, model)

        if elbows.empty?
          elbow_label = "No catalog elbow for this size (straight runs only)"
          elbow_input = ::UI.inputbox(
            ["Elbow Product:", "Length Increment:"],
            [elbow_label, increment_label(current_increment)],
            [elbow_label, "1/4 inch|1/2 inch|1 inch"],
            "#{active_name(model)} Routing Product"
          )
          return nil unless elbow_input
          chosen_elbow = nil
          increment_value = elbow_input[1]
        else
          preferred = preferred_elbow(model, dimensions) || elbows.first
          elbow_labels = elbows.map(&:label)
          elbow_input = ::UI.inputbox(
            ["Elbow Product:", "Length Increment:"],
            [preferred.label, increment_label(current_increment)],
            [elbow_labels.join("|"), "1/4 inch|1/2 inch|1 inch"],
            "#{active_name(model)} Routing Product"
          )
          return nil unless elbow_input
          chosen_elbow = elbows.find { |p| p.label == elbow_input[0].to_s } || preferred
          increment_value = elbow_input[1]
          save_elbow_preference(model, dimensions, chosen_elbow)
        end

        {
          shape: dimensions[:shape],
          diameter: dimensions[:diameter],
          width: dimensions[:width],
          height: dimensions[:height],
          length_increment: increment_from_label(increment_value, current_increment),
          pipe_product: selected,
          elbow_product: chosen_elbow
        }
      rescue => error
        puts "Catalog::Manager.prompt_duct_settings failed: #{error.message}"
        nil
      end

      def prompt_branch_dimensions(main_dimensions:, family:, title:, model: nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        return nil unless active?(model)

        main = Model::DuctDimensions.coerce(main_dimensions)
        products = junction_products(main, family, model)
        targets = allowed_branch_targets(main, family: family, model: model)

        if products.empty? || targets.empty?
          ::UI.messagebox("#{active_name(model)} has no modeled #{family} product with an inlet matching this duct size.")
          return nil
        end

        preferred = preferred_junction(model, main, family) || products.first
        product_labels = products.map(&:label)
        target_labels = targets.map do |dims|
          transition = transition_product(main, dims, model)
          if transition
            "#{transition.sku} — branch becomes #{dimensions_label(dims)}"
          else
            "No transition — #{dimensions_label(dims)}"
          end
        end

        input = ::UI.inputbox(
          ["#{family.to_s.capitalize} Product:", "Branch Product / Size:"],
          [preferred.label, target_labels.first],
          [product_labels.join("|"), target_labels.join("|")],
          title
        )
        return nil unless input

        selected_product = products.find { |product| product.label == input[0].to_s } || preferred
        save_junction_preference(model, main, family, selected_product)

        index = target_labels.index(input[1].to_s) || 0
        targets[index]
      rescue => error
        puts "Catalog::Manager.prompt_branch_dimensions failed: #{error.message}"
        nil
      end

      def prompt_transition_target(source_dimensions, title:, model: nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        targets = transition_targets(source_dimensions, model)
        if targets.empty?
          ::UI.messagebox("There is no #{active_name(model)} reducer/converter in the loaded catalog that connects from this size.")
          return nil
        end

        products = targets.map { |dims| transition_product(source_dimensions, dims, model) }
        labels = targets.each_with_index.map do |dims, index|
          product = products[index]
          "#{product ? product.sku : 'Catalog transition'} — #{dimensions_label(dims)}"
        end

        input = ::UI.inputbox(["Target Product / Size:"], [labels.first], [labels.join("|")], title)
        return nil unless input

        index = labels.index(input[0].to_s) || 0
        target = targets[index]
        product = products[index]
        {
          dimensions: target,
          product: product,
          length: transition_length(product, Geometry::ReducerBuilder.default_length(source_dimensions, target))
        }
      rescue => error
        puts "Catalog::Manager.prompt_transition_target failed: #{error.message}"
        nil
      end

      def apply_product_metadata(group, product, extra = {})
        return false unless group && group.valid? && product

        group.set_attribute(DICTIONARY, "catalog_key", product_catalog_key(product).to_s)
        group.set_attribute(DICTIONARY, "catalog_name", product_catalog_name(product))
        group.set_attribute(DICTIONARY, "model_number", product.sku.to_s)
        group.set_attribute(DICTIONARY, "product_name", product.name.to_s)
        group.set_attribute(DICTIONARY, "family", product.family.to_s)
        group.set_attribute(DICTIONARY, "nominal_shape", product.shape.to_s)
        group.set_attribute(DICTIONARY, "nominal_diameter", product.diameter.to_f) if product.diameter
        group.set_attribute(DICTIONARY, "nominal_width", product.width.to_f) if product.width
        group.set_attribute(DICTIONARY, "nominal_height", product.height.to_f) if product.height
        group.set_attribute(DICTIONARY, "branch_diameter", product.branch_diameter.to_f) if product.branch_diameter
        group.set_attribute(DICTIONARY, "catalog_document", product_catalog_document(product))

        if product.overall
          product.overall.each do |key, value|
            group.set_attribute(DICTIONARY, "overall_#{key}", value.to_f)
          end
        end

        extra.each { |key, value| group.set_attribute(DICTIONARY, key.to_s, value) }
        true
      rescue => error
        puts "Catalog::Manager.apply_product_metadata failed: #{error.message}"
        false
      end

      def tag_piece(piece, product, extra = {})
        return false unless piece && piece.group
        apply_product_metadata(piece.group, product, extra)
      end

      def unsupported_message(family, dimensions = nil)
        detail = dimensions ? " for #{dimensions_label(dimensions)}" : ""
        "#{active_name} catalog mode has no supported #{family.to_s.tr('_', ' ')}#{detail} in the loaded catalog. No generic fitting was created."
      end

      def notify_unsupported(family, dimensions = nil)
        message = unsupported_message(family, dimensions)
        puts message
        ::UI.messagebox(message) if defined?(::UI)
        nil
      rescue
        nil
      end

      def dimensions_for_pipe_product(product)
        if product.shape.to_sym == :round
          Model::DuctDimensions.round(diameter: product.diameter)
        else
          Model::DuctDimensions.rectangular(width: product.width, height: product.height)
        end
      end

      def dimensions_label(dimensions)
        dims = Model::DuctDimensions.coerce(dimensions)
        if dims.round?
          "#{number_label(dims.diameter)}\" round"
        else
          "#{number_label(dims.width)}\" x #{number_label(dims.height)}\" rectangular"
        end
      rescue
        "unknown size"
      end

      def dimensions_signature(dimensions)
        dims = Model::DuctDimensions.coerce(dimensions)
        if dims.round?
          "round_#{number_label(dims.diameter).tr('.', '_')}"
        else
          a, b = [dims.width.to_f, dims.height.to_f].sort.reverse
          "rect_#{number_label(a).tr('.', '_')}_#{number_label(b).tr('.', '_')}"
        end
      rescue
        "unknown"
      end

      def rectangular_size_match?(a_width, a_height, b_width, b_height)
        direct = close?(a_width, b_width) && close?(a_height, b_height)
        swapped = close?(a_width, b_height) && close?(a_height, b_width)
        direct || swapped
      end

      def close?(a, b)
        (a.to_f - b.to_f).abs <= TOLERANCE
      end

      def unique_dimensions(values)
        seen = {}
        Array(values).each_with_object([]) do |dims, result|
          key = dimensions_signature(dims)
          next if seen[key]
          seen[key] = true
          result << dims
        end
      end

      def increment_label(value)
        case value.to_f
        when 0.5 then "1/2 inch"
        when 1.0 then "1 inch"
        else "1/4 inch"
        end
      end

      def increment_from_label(value, fallback)
        case value.to_s
        when "1/2 inch" then 0.5
        when "1 inch" then 1.0
        when "1/4 inch" then 0.25
        else fallback.to_f > 0.0 ? fallback.to_f : 0.25
        end
      end

      def number_label(value)
        number = value.to_f
        (number - number.round).abs < 0.0001 ? number.round.to_s : number.to_s.sub(/0+$/, '').sub(/\.$/, '')
      end
    end
  end
end

# ===== Catalog-mode UX and rigid-product helpers =====
module DuctExtension
  module Catalog
    module Manager
      module_function

      def catalog_locked_piece?(piece_or_group)
        group = piece_or_group.respond_to?(:group) ? piece_or_group.group : piece_or_group
        return false unless group && group.valid?
        key = group.get_attribute(DICTIONARY, "catalog_key")
        !key.to_s.empty? && key.to_s != BASE_KEY.to_s
      rescue
        false
      end

      def junction_products(dimensions, family, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        return [] unless dims.round?

        all_products(model).select do |product|
          product.family == family.to_sym && close?(product.diameter, dims.diameter)
        end
      rescue
        []
      end

      def prompt_junction_product(main_dimensions:, family:, title:, model: nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        return nil unless active?(model)

        products = junction_products(main_dimensions, family, model)
        if products.empty?
          ::UI.messagebox("#{active_name(model)} has no #{family} with an inlet matching #{dimensions_label(main_dimensions)}.")
          return nil
        end

        preferred = preferred_junction(model, main_dimensions, family) || products.first
        input = ::UI.inputbox(
          ["#{family.to_s.capitalize} Product:"],
          [preferred.label],
          [products.map(&:label).join("|")],
          title
        )
        return nil unless input

        chosen = products.find { |product| product.label == input[0].to_s } || preferred
        save_junction_preference(model, main_dimensions, family, chosen)
        chosen
      rescue => error
        puts "Catalog::Manager.prompt_junction_product failed: #{error.message}"
        nil
      end

      def wye_output_dimensions(product)
        return nil unless product && product.family == :wye
        diameter = (product.outlet_diameter || product.branch_diameter || product.diameter).to_f
        return nil unless diameter > 0.0
        Model::DuctDimensions.round(diameter: diameter)
      rescue
        nil
      end

      def compatible_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)

        all_products(model).select do |product|
          case product.family
          when :pipe, :elbow, :tee, :wye
            if dims.round?
              product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
            else
              product.shape.to_sym == :rectangular && rectangular_size_match?(
                product.width, product.height, dims.width, dims.height
              )
            end
          when :transition
            if product.shape.to_sym == :round && dims.round?
              close?(product.diameter, dims.diameter) || close?(product.branch_diameter, dims.diameter)
            elsif product.shape.to_sym == :mixed
              (dims.round? && close?(product.diameter, dims.diameter)) ||
                (dims.rectangular? && rectangular_size_match?(product.width, product.height, dims.width, dims.height))
            else
              false
            end
          when :end_cover
            dims.rectangular? && rectangular_size_match?(product.width, product.height, dims.width, dims.height)
          else
            false
          end
        end
      rescue
        []
      end

      def products_grouped_by_family(model = nil)
        groups = Hash.new { |hash, key| hash[key] = [] }
        all_products(model).each { |product| groups[product.family] << product }
        groups
      end

      def size_availability_text(dimensions, model = nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        dims = Model::DuctDimensions.coerce(dimensions)
        products = compatible_products(dims, model)
        groups = products.group_by(&:family)

        labels = {
          pipe: "Straight duct",
          elbow: "Elbows",
          tee: "Tees",
          wye: "Wyes",
          transition: "Reducers / converters",
          end_cover: "End covers"
        }

        lines = ["Master Flow options for #{dimensions_label(dims)}:"]
        labels.each do |family, label|
          matches = Array(groups[family])
          if matches.empty?
            lines << "  #{label}: none"
          else
            lines << "  #{label}: #{matches.map(&:sku).join(', ')}"
          end
        end
        lines.join("\n")
      rescue
        "No availability summary could be generated."
      end

      def show_catalog_browser(model = nil, dimensions: nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        unless active?(model)
          ::UI.messagebox("No product catalog is active. Choose Set Catalog... first.")
          return false
        end

        if defined?(::UI::HtmlDialog)
          dialog = ::UI::HtmlDialog.new(
            dialog_title: "#{active_name(model)} Catalog — Supported Simple Duct Products",
            preferences_key: "SimpleDuctCatalogBrowser",
            scrollable: true,
            resizable: true,
            width: 900,
            height: 720,
            style: ::UI::HtmlDialog::STYLE_DIALOG
          )
          dialog.set_html(catalog_browser_html(model, dimensions: dimensions))
          dialog.show
          @catalog_browser_dialog = dialog
          true
        else
          text = dimensions ? size_availability_text(dimensions, model) : catalog_plain_text(model)
          ::UI.messagebox(text)
          true
        end
      rescue => error
        puts "Catalog::Manager.show_catalog_browser failed: #{error.message}"
        ::UI.messagebox(catalog_plain_text(model)) rescue nil
        false
      end

      def catalog_browser_html(model, dimensions: nil)
        current = dimensions && Model::DuctDimensions.coerce(dimensions)
        groups = products_grouped_by_family(model)
        family_names = {
          pipe: "Straight Duct",
          elbow: "Elbows",
          tee: "Tees",
          wye: "Wyes",
          transition: "Reducers / Stack Boots",
          end_cover: "End Covers"
        }

        rows = family_names.map do |family, heading|
          products = Array(groups[family]).sort_by { |p| [p.shape.to_s, p.diameter.to_f, p.width.to_f, p.sku.to_s] }
          body = products.map do |product|
            compatible = current ? compatible_products(current, model).include?(product) : false
            klass = compatible ? "compatible" : ""
            "<tr class='#{klass}'><td><b>#{html_escape(product.sku)}</b></td><td>#{html_escape(product.name)}</td><td>#{html_escape(product_connector_text(product))}</td></tr>"
          end.join
          "<section><h2>#{heading}</h2><table><thead><tr><th>Model</th><th>Product</th><th>Connections / size</th></tr></thead><tbody>#{body}</tbody></table></section>"
        end.join

        current_html =
          if current
            "<div class='current'><b>Current duct:</b> #{html_escape(dimensions_label(current))}. Highlighted rows can connect to or are this size.</div>"
          else
            "<div class='current'>Tip: open this browser from the drawing tool to highlight products compatible with the current duct size.</div>"
          end

        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
          body{font-family:Arial,sans-serif;margin:18px;color:#222;background:#fafafa}
          h1{margin:0 0 8px;font-size:24px} h2{font-size:18px;margin-top:26px;border-bottom:1px solid #bbb;padding-bottom:5px}
          .current{background:#eef5ff;border:1px solid #9bbce6;padding:10px 12px;border-radius:6px;margin:14px 0}
          .note{font-size:13px;color:#555;margin-bottom:14px}
          table{border-collapse:collapse;width:100%;background:white} th,td{border:1px solid #ddd;padding:7px;text-align:left;vertical-align:top}
          th{background:#eee}.compatible{background:#e8f7e8}.legend{font-size:12px;margin-top:6px}.swatch{display:inline-block;width:12px;height:12px;background:#e8f7e8;border:1px solid #aaa;vertical-align:middle}
          </style></head><body>
          <h1>Master Flow — supported catalog products</h1>
          <div class="note">Only product families Simple Duct currently knows how to model are listed. No generic fitting is substituted when a required catalog product does not exist.</div>
          #{current_html}
          <div class="legend"><span class="swatch"></span> compatible with current duct</div>
          #{rows}
          </body></html>
        HTML
      end
      private_class_method :catalog_browser_html

      def catalog_plain_text(model)
        groups = products_grouped_by_family(model)
        groups.keys.sort_by(&:to_s).map do |family|
          "#{family.to_s.upcase}:\n  " + groups[family].map(&:sku).join(", ")
        end.join("\n\n")
      rescue
        "#{active_name(model)} catalog"
      end
      private_class_method :catalog_plain_text

      def product_connector_text(product)
        case product.family
        when :pipe
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" round; continuous model run"
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\"; continuous model run"
          end
        when :elbow
          product.shape.to_sym == :round ? "#{number_label(product.diameter)}\" round, 90° configured" : "#{number_label(product.width)}\" × #{number_label(product.height)}\", 90°"
        when :tee
          "#{number_label(product.diameter)}\" × #{number_label(product.diameter)}\" × #{number_label(product.diameter)}\""
        when :wye
          outlet = product.outlet_diameter || product.branch_diameter || product.diameter
          "#{number_label(product.diameter)}\" inlet → #{number_label(outlet)}\" + #{number_label(outlet)}\""
        when :transition
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" ↔ #{number_label(product.branch_diameter)}\""
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\" ↔ #{number_label(product.diameter)}\" round"
          end
        when :end_cover
          "#{number_label(product.width)}\" × #{number_label(product.height)}\""
        else
          ""
        end
      end
      private_class_method :product_connector_text

      def html_escape(text)
        text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end
      private_class_method :html_escape

      # ---- Catalog v3 usability / coverage helpers ---------------------------

      def end_cover_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)

        all_products(model).select do |product|
          next false unless product.family == :end_cover

          if dims.round?
            product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
          else
            product.shape.to_sym == :rectangular && rectangular_size_match?(
              product.width, product.height, dims.width, dims.height
            )
          end
        end
      rescue
        []
      end

      def end_cover_product(dimensions, model = nil)
        end_cover_products(dimensions, model).first
      rescue
        nil
      end

      def compatible_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)

        all_products(model).select do |product|
          case product.family
          when :pipe, :elbow, :tee, :wye
            if dims.round?
              product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
            else
              product.shape.to_sym == :rectangular && rectangular_size_match?(
                product.width, product.height, dims.width, dims.height
              )
            end
          when :transition
            if product.shape.to_sym == :round && dims.round?
              close?(product.diameter, dims.diameter) || close?(product.branch_diameter, dims.diameter)
            elsif product.shape.to_sym == :mixed
              (dims.round? && close?(product.diameter, dims.diameter)) ||
                (dims.rectangular? && rectangular_size_match?(product.width, product.height, dims.width, dims.height))
            else
              false
            end
          when :end_cover
            if dims.round?
              product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
            else
              product.shape.to_sym == :rectangular && rectangular_size_match?(
                product.width, product.height, dims.width, dims.height
              )
            end
          else
            false
          end
        end
      rescue
        []
      end

      def pipe_buildability(product, model = nil)
        return {} unless product && product.family == :pipe
        dims = dimensions_for_pipe_product(product)
        {
          dimensions: dims,
          elbows: elbow_products(dims, model),
          tees: junction_products(dims, :tee, model),
          wyes: junction_products(dims, :wye, model),
          transitions: transition_targets(dims, model),
          covers: end_cover_products(dims, model)
        }
      rescue
        {}
      end

      def pipe_selection_label(product, model = nil)
        availability = pipe_buildability(product, model)
        elbows = Array(availability[:elbows])
        turn_text = elbows.empty? ? "STRAIGHT-ONLY: no catalog elbow" : "turns: #{elbows.map(&:sku).join(' / ')}"
        "#{product.label}  [#{turn_text}]"
      rescue
        product ? product.label : "Unknown catalog product"
      end

      # Catalog mode now warns about a straight product that has no corresponding
      # elbow before the user commits to it. The product is still available because
      # it genuinely exists in RESMF164; the UI simply makes its limitations clear.
      def prompt_duct_settings(
        model:,
        current_shape:,
        current_diameter:,
        current_width:,
        current_height:,
        current_increment:
      )
        shape_input = ::UI.inputbox(
          ["Duct Shape:"],
          [current_shape.to_sym == :rectangular ? "Rectangular" : "Round"],
          ["Round|Rectangular"],
          "#{active_name(model)} Duct Settings"
        )
        return nil unless shape_input

        shape = shape_input[0].to_s.downcase.start_with?("rect") ? :rectangular : :round
        products = pipe_products(shape, model)
        if products.empty?
          ::UI.messagebox("No #{active_name(model)} #{shape} straight-duct product exists in the loaded catalog.")
          return nil
        end

        current_dims =
          if shape == :round
            Model::DuctDimensions.round(diameter: current_diameter)
          else
            Model::DuctDimensions.rectangular(width: current_width, height: current_height)
          end

        selected = pipe_product(current_dims, model) || products.first
        labels = products.map { |product| pipe_selection_label(product, model) }
        default_label = pipe_selection_label(selected, model)

        product_input = ::UI.inputbox(
          ["Duct Product:"],
          [default_label],
          [labels.join("|")],
          "#{active_name(model)} Duct Product"
        )
        return nil unless product_input

        selected_index = labels.index(product_input[0].to_s)
        selected = selected_index ? products[selected_index] : selected
        dimensions = dimensions_for_pipe_product(selected)
        save_pipe_preference(model, dimensions, selected)
        elbows = elbow_products(dimensions, model)

        if elbows.empty?
          availability = size_availability_text(dimensions, model)
          warning =
            "#{selected.sku} is a real #{active_name(model)} straight-duct product, but the loaded catalog lists no matching elbow for #{dimensions_label(dimensions)}.\n\n" \
            "In strict catalog mode this size can continue straight and can use only the compatible products listed below; Simple Duct will not invent a generic elbow.\n\n" \
            "#{availability}\n\nContinue with this straight-only size?"
          answer = ::UI.messagebox(warning, MB_YESNO)
          return nil unless answer == IDYES

          elbow_label = "No catalog elbow for this size — straight continuation only"
          elbow_input = ::UI.inputbox(
            ["Elbow Product:", "Length Increment:"],
            [elbow_label, increment_label(current_increment)],
            [elbow_label, "1/4 inch|1/2 inch|1 inch"],
            "#{active_name(model)} Routing Product"
          )
          return nil unless elbow_input
          chosen_elbow = nil
          increment_value = elbow_input[1]
        else
          preferred = preferred_elbow(model, dimensions) || elbows.first
          elbow_labels = elbows.map(&:label)
          elbow_input = ::UI.inputbox(
            ["Elbow Product:", "Length Increment:"],
            [preferred.label, increment_label(current_increment)],
            [elbow_labels.join("|"), "1/4 inch|1/2 inch|1 inch"],
            "#{active_name(model)} Routing Product"
          )
          return nil unless elbow_input
          chosen_elbow = elbows.find { |product| product.label == elbow_input[0].to_s } || preferred
          increment_value = elbow_input[1]
          save_elbow_preference(model, dimensions, chosen_elbow)
        end

        {
          shape: dimensions[:shape],
          diameter: dimensions[:diameter],
          width: dimensions[:width],
          height: dimensions[:height],
          length_increment: increment_from_label(increment_value, current_increment),
          pipe_product: selected,
          elbow_product: chosen_elbow
        }
      rescue => error
        puts "Catalog::Manager.prompt_duct_settings failed: #{error.message}"
        puts error.backtrace.join("\n")
        nil
      end

      def catalog_size_rows(model = nil)
        rows = {}
        pipe_products(:round, model).each do |product|
          dims = dimensions_for_pipe_product(product)
          key = dimensions_signature(dims)
          rows[key] ||= { dimensions: dims, pipes: [] }
          rows[key][:pipes] << product
        end
        pipe_products(:rectangular, model).each do |product|
          dims = dimensions_for_pipe_product(product)
          key = dimensions_signature(dims)
          rows[key] ||= { dimensions: dims, pipes: [] }
          rows[key][:pipes] << product
        end

        rows.values.each do |row|
          dims = row[:dimensions]
          row[:elbows] = elbow_products(dims, model)
          row[:tees] = junction_products(dims, :tee, model)
          row[:wyes] = junction_products(dims, :wye, model)
          row[:transitions] = compatible_products(dims, model).select { |p| p.family == :transition }
          row[:covers] = end_cover_products(dims, model)
        end

        rows.values.sort_by do |row|
          dims = row[:dimensions]
          dims.round? ? [0, dims.diameter.to_f, 0] : [1, -dims.width.to_f, -dims.height.to_f]
        end
      rescue
        []
      end

      def catalog_browser_html(model, dimensions: nil)
        current = dimensions && Model::DuctDimensions.coerce(dimensions)
        groups = products_grouped_by_family(model)
        family_names = {
          pipe: "Straight Duct",
          elbow: "Elbows",
          tee: "Tees",
          wye: "Wyes",
          transition: "Reducers / Stack Boots",
          end_cover: "End Covers"
        }

        availability_rows = catalog_size_rows(model).map do |row|
          dims = row[:dimensions]
          is_current = current && dimensions_signature(current) == dimensions_signature(dims)
          has_elbow = !Array(row[:elbows]).empty?
          css = [is_current ? "current-row" : nil, has_elbow ? nil : "straight-only"].compact.join(" ")
          transitions = Array(row[:transitions]).map(&:sku)
          <<~ROW
            <tr class="#{css}">
              <td><b>#{html_escape(dimensions_label(dims))}</b></td>
              <td>#{html_escape(Array(row[:pipes]).map(&:sku).join(', '))}</td>
              <td>#{html_escape(Array(row[:elbows]).map(&:sku).join(', ').yield_self { |x| x.empty? ? 'NONE' : x })}</td>
              <td>#{html_escape(Array(row[:tees]).map(&:sku).join(', ').yield_self { |x| x.empty? ? '—' : x })}</td>
              <td>#{html_escape(Array(row[:wyes]).map(&:sku).join(', ').yield_self { |x| x.empty? ? '—' : x })}</td>
              <td>#{html_escape(transitions.join(', ').yield_self { |x| x.empty? ? '—' : x })}</td>
              <td>#{html_escape(Array(row[:covers]).map(&:sku).join(', ').yield_self { |x| x.empty? ? '—' : x })}</td>
              <td><b>#{has_elbow ? 'TURNABLE' : 'STRAIGHT ONLY'}</b></td>
            </tr>
          ROW
        end.join

        details = family_names.map do |family, heading|
          products = Array(groups[family]).sort_by { |p| [p.shape.to_s, p.diameter.to_f, p.width.to_f, p.sku.to_s] }
          body = products.map do |product|
            compatible = current ? compatible_products(current, model).include?(product) : false
            klass = compatible ? "compatible" : ""
            "<tr class='#{klass}'><td><b>#{html_escape(product.sku)}</b></td><td>#{html_escape(product.name)}</td><td>#{html_escape(product_connector_text(product))}</td><td>#{html_escape(product_envelope_text(product))}</td></tr>"
          end.join
          "<section><h2>#{heading}</h2><table><thead><tr><th>Model</th><th>Product</th><th>Catalog connections / size</th><th>Loaded physical envelope</th></tr></thead><tbody>#{body}</tbody></table></section>"
        end.join

        current_html =
          if current
            "<div class='current'><b>Current duct:</b> #{html_escape(dimensions_label(current))}. The matching size row and compatible products are highlighted.</div>"
          else
            "<div class='current'>Start here: the table below shows which straight duct sizes can actually turn, branch, transition, or terminate using the loaded Master Flow catalog.</div>"
          end

        <<~HTML
          <!doctype html>
          <html><head><meta charset="utf-8"><style>
          body{font-family:Arial,sans-serif;margin:18px;color:#222;background:#fafafa}
          h1{margin:0 0 8px;font-size:24px} h2{font-size:18px;margin-top:28px;border-bottom:1px solid #bbb;padding-bottom:5px}
          .current{background:#eef5ff;border:1px solid #9bbce6;padding:10px 12px;border-radius:6px;margin:14px 0}
          .note{font-size:13px;color:#555;margin-bottom:14px}.warning{background:#fff2d9;border:1px solid #e0aa55;padding:9px 11px;border-radius:5px;margin:12px 0}
          table{border-collapse:collapse;width:100%;background:white} th,td{border:1px solid #ddd;padding:7px;text-align:left;vertical-align:top}
          th{background:#eee;position:sticky;top:0}.compatible,.current-row{background:#e8f7e8}.straight-only{background:#fff0f0}.current-row.straight-only{background:#ffe6cc}
          .legend{font-size:12px;margin:8px 0}.green,.red{display:inline-block;width:12px;height:12px;border:1px solid #aaa;vertical-align:middle;margin-right:4px}.green{background:#e8f7e8}.red{background:#fff0f0}
          </style></head><body>
          <h1>Master Flow — Simple Duct catalog</h1>
          <div class="note">Only product families Simple Duct currently models are shown. A missing fitting is treated as genuinely unavailable in strict catalog mode; the extension does not substitute generic geometry. SKU/model numbers and nominal connector sizes are the catalog-authoritative values. Physical-envelope values are shown separately only where a measurement is loaded, so nominal size is never confused with body geometry. Round adjustable elbows may be modeled at installed angles through 90°. Straight runs are modeled as continuous arbitrary-length pieces with no intermediate section joints or piece-count segmentation.</div>
          #{current_html}
          <div class="warning"><b>Important:</b> Master Flow sells several rectangular straight-duct sizes without a matching elbow in RESMF164. Those rows are intentionally marked <b>STRAIGHT ONLY</b>.</div>
          <h2>Buildability by duct size</h2>
          <div class="legend"><span class="green"></span> current/turnable &nbsp;&nbsp; <span class="red"></span> no catalog elbow</div>
          <table><thead><tr><th>Duct size</th><th>Straight SKU(s)</th><th>Elbow(s)</th><th>Tee(s)</th><th>Wye(s)</th><th>Transitions</th><th>Caps</th><th>Routing</th></tr></thead><tbody>#{availability_rows}</tbody></table>
          #{details}
          </body></html>
        HTML
      end
      private_class_method :catalog_browser_html

      def product_connector_text(product)
        case product.family
        when :pipe
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" round; continuous model run"
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\"; continuous model run"
          end
        when :elbow
          product.shape.to_sym == :round ? "#{number_label(product.diameter)}\" round, 90° configured" : "#{number_label(product.width)}\" × #{number_label(product.height)}\", 90°"
        when :tee
          "#{number_label(product.diameter)}\" × #{number_label(product.diameter)}\" × #{number_label(product.diameter)}\""
        when :wye
          outlet = product.outlet_diameter || product.branch_diameter || product.diameter
          "#{number_label(product.diameter)}\" inlet → #{number_label(outlet)}\" + #{number_label(outlet)}\""
        when :transition
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" ↔ #{number_label(product.branch_diameter)}\""
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\" ↔ #{number_label(product.diameter)}\" round"
          end
        when :end_cover
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" round"
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\""
          end
        else
          ""
        end
      end
      private_class_method :product_connector_text

      def product_envelope_text(product)
        overall = product && product.overall
        return "—" unless overall.is_a?(Hash) && !overall.empty?

        parts = []
        parts << "H #{number_label(overall[:height])}\"" if overall[:height].to_f > 0.0
        parts << "W #{number_label(overall[:width])}\"" if overall[:width].to_f > 0.0
        parts << "L #{number_label(overall[:length])}\"" if overall[:length].to_f > 0.0
        parts << "Ø #{number_label(overall[:diameter])}\"" if overall[:diameter].to_f > 0.0
        parts << "D #{number_label(overall[:depth])}\"" if overall[:depth].to_f > 0.0

        radius = overall[:derived_centerline_radius].to_f
        parts << "90° CLR #{number_label(radius)}\"" if radius > 0.0
        parts.empty? ? "—" : parts.join(" × ")
      rescue
        "—"
      end
      private_class_method :product_envelope_text

      # Use the catalog-specific elbow geometry when available. For adjustable
      # round elbows the 90° envelope is the reference, and the effective radius
      # increases at smaller angles so the fitting keeps its developed length.
      def elbow_bend_radius(product, dimensions, fallback, angle: nil)
        return fallback.to_f unless product
        if defined?(MasterFlowGeometry) && MasterFlowGeometry.respond_to?(:elbow_radius)
          value = MasterFlowGeometry.elbow_radius(product, dimensions, angle: angle).to_f
          return value if value > 0.0
        end
        fallback.to_f
      rescue
        fallback.to_f
      end

      def elbow_angle_supported?(product, dimensions, angle)
        return true unless active?(Sketchup.active_model)
        return false unless product
        return MasterFlowGeometry.elbow_angle_supported?(product, dimensions, angle) if defined?(MasterFlowGeometry)
        false
      rescue
        false
      end

      def elbow_angle_status(product, dimensions, angle)
        dims = Model::DuctDimensions.coerce(dimensions)
        degrees = angle.to_f * 180.0 / Math::PI
        if dims.round? && product && product.style == :four_gore_adjustable
          "#{product_catalog_name(product)} #{product.sku}: adjustable round elbows support modeled turns through 90°; nearly straight directions use straight duct. Requested #{degrees.round(1)}°."
        else
          "#{product_catalog_name(product)} #{product && product.sku}: this catalog elbow is fixed at #{(product && product.angle_degrees || 90).to_f.round(1)}°. Requested #{degrees.round(1)}°."
        end
      rescue
        "Requested catalog elbow angle is not supported."
      end
    end
  end
end

# ===== v5.1 catalog saddle / register-box extensions =====
module DuctExtension
  module Catalog
    module Manager
      module_function

      def tee_saddle_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        return [] unless dims.round?
        all_products(model).select do |product|
          product.family == :tee_saddle &&
            (product.style == :tee_saddle_equal_or_larger ?
              dims.diameter.to_f + 0.001 >= product.diameter.to_f :
              close?(product.diameter, dims.diameter))
        end.sort_by do |product|
          exact = close?(product.diameter, dims.diameter) ? 0 : 1
          [exact, -product.diameter.to_f]
        end
      rescue
        []
      end

      def tee_saddle_product(dimensions, model = nil)
        tee_saddle_products(dimensions, model).first
      rescue
        nil
      end

      def wye_saddle_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        return [] unless dims.round?
        all_products(model).select do |product|
          product.family == :wye_saddle && dims.diameter.to_f + 0.001 >= product.diameter.to_f
        end.sort_by do |product|
          exact = close?(product.diameter, dims.diameter) ? 0 : 1
          [exact, -product.diameter.to_f]
        end
      rescue
        []
      end

      def wye_saddle_product(dimensions, model = nil)
        wye_saddle_products(dimensions, model).first
      rescue
        nil
      end

      def register_box_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        return [] unless dims.round?
        all_products(model).select do |product|
          product.family == :register_box && close?(product.diameter, dims.diameter)
        end
      rescue
        []
      end

      def register_box_saddle_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        return [] unless dims.round?
        all_products(model).select do |product|
          product.family == :register_box_saddle && close?(product.diameter, dims.diameter)
        end
      rescue
        []
      end

      def wall_vent_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        all_products(model).select do |product|
          next false unless product.family == :wall_vent
          if dims.round?
            product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
          else
            product.shape.to_sym == :rectangular && rectangular_size_match?(
              product.width, product.height, dims.width, dims.height
            )
          end
        end
      rescue
        []
      end

      def fresh_air_vent_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)
        return [] unless dims.round?
        all_products(model).select do |product|
          product.family == :fresh_air_vent && close?(product.diameter, dims.diameter)
        end
      rescue
        []
      end

      def prompt_product_from(products, title:, label: "Product:")
        products = Array(products)
        return nil if products.empty?
        return products.first if products.length == 1
        input = ::UI.inputbox(
          [label],
          [products.first.label],
          [products.map(&:label).join("|")],
          title
        )
        return nil unless input
        products.find { |product| product.label == input[0].to_s } || products.first
      rescue => error
        puts "Catalog::Manager.prompt_product_from failed: #{error.message}"
        nil
      end

      def prompt_terminal_product(dimensions, model = nil)
        products =
          end_cover_products(dimensions, model) +
          register_box_products(dimensions, model) +
          wall_vent_products(dimensions, model) +
          fresh_air_vent_products(dimensions, model)
        prompt_product_from(products, title: "Master Flow End Component", label: "End Product:")
      end

      def prompt_register_box_saddle(dimensions, model = nil)
        prompt_product_from(
          register_box_saddle_products(dimensions, model),
          title: "Master Flow Side Register",
          label: "Register Saddle:"
        )
      end

      def compatible_products(dimensions, model = nil)
        return [] unless active?(model)
        dims = Model::DuctDimensions.coerce(dimensions)

        all_products(model).select do |product|
          case product.family
          when :pipe, :elbow, :tee, :wye
            if dims.round?
              product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
            else
              product.shape.to_sym == :rectangular && rectangular_size_match?(
                product.width, product.height, dims.width, dims.height
              )
            end
          when :tee_saddle
            dims.round? && (product.style == :tee_saddle_equal_or_larger ?
              dims.diameter.to_f + 0.001 >= product.diameter.to_f :
              close?(product.diameter, dims.diameter))
          when :wye_saddle
            dims.round? && dims.diameter.to_f + 0.001 >= product.diameter.to_f
          when :register_box, :register_box_saddle
            dims.round? && close?(product.diameter, dims.diameter)
          when :wall_vent
            if dims.round?
              product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
            else
              product.shape.to_sym == :rectangular && rectangular_size_match?(
                product.width, product.height, dims.width, dims.height
              )
            end
          when :fresh_air_vent
            dims.round? && product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
          when :transition
            if product.shape.to_sym == :round && dims.round?
              close?(product.diameter, dims.diameter) || close?(product.branch_diameter, dims.diameter)
            elsif product.shape.to_sym == :mixed
              (dims.round? && close?(product.diameter, dims.diameter)) ||
                (dims.rectangular? && rectangular_size_match?(product.width, product.height, dims.width, dims.height))
            else
              false
            end
          when :end_cover
            if dims.round?
              product.shape.to_sym == :round && close?(product.diameter, dims.diameter)
            else
              product.shape.to_sym == :rectangular && rectangular_size_match?(
                product.width, product.height, dims.width, dims.height
              )
            end
          else
            false
          end
        end
      rescue
        []
      end

      def catalog_size_rows(model = nil)
        rows = {}
        [:round, :rectangular].each do |shape|
          pipe_products(shape, model).each do |product|
            dims = dimensions_for_pipe_product(product)
            key = dimensions_signature(dims)
            rows[key] ||= { dimensions: dims, pipes: [] }
            rows[key][:pipes] << product
          end
        end

        rows.values.each do |row|
          dims = row[:dimensions]
          row[:elbows] = elbow_products(dims, model)
          row[:tees] = junction_products(dims, :tee, model)
          row[:wyes] = junction_products(dims, :wye, model)
          row[:tee_saddles] = tee_saddle_products(dims, model)
          row[:wye_saddles] = wye_saddle_products(dims, model)
          row[:transitions] = compatible_products(dims, model).select { |p| p.family == :transition }
          row[:register_boxes] = register_box_products(dims, model)
          row[:register_saddles] = register_box_saddle_products(dims, model)
          row[:wall_vents] = wall_vent_products(dims, model)
          row[:fresh_air_vents] = fresh_air_vent_products(dims, model)
          row[:covers] = end_cover_products(dims, model)
        end

        rows.values.sort_by do |row|
          dims = row[:dimensions]
          dims.round? ? [0, dims.diameter.to_f, 0] : [1, -dims.width.to_f, -dims.height.to_f]
        end
      rescue
        []
      end

      def size_availability_text(dimensions, model = nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        dims = Model::DuctDimensions.coerce(dimensions)
        products = compatible_products(dims, model)
        groups = products.group_by(&:family)
        labels = {
          pipe: "Straight duct",
          elbow: "Elbows",
          tee: "Full-flow tees",
          tee_saddle: "Inline tee saddles",
          wye: "Full-flow wyes",
          wye_saddle: "Inline wye saddles",
          transition: "Reducers / converters",
          register_box: "End register boxes",
          register_box_saddle: "Side register saddles",
          wall_vent: "Exterior wall vents",
          fresh_air_vent: "Fresh-air intake vents",
          end_cover: "End covers"
        }
        lines = ["Master Flow options for #{dimensions_label(dims)}:"]
        labels.each do |family, label|
          matches = Array(groups[family])
          lines << "  #{label}: #{matches.empty? ? 'none' : matches.map(&:sku).join(', ')}"
        end
        lines.join("\n")
      rescue
        "No availability summary could be generated."
      end

      def catalog_browser_html(model, dimensions: nil)
        current = dimensions && Model::DuctDimensions.coerce(dimensions)
        groups = products_grouped_by_family(model)
        family_names = {
          pipe: "Straight Duct",
          elbow: "Elbows",
          tee: "Full-Flow Tees",
          tee_saddle: "Inline Tee Saddles",
          wye: "Full-Flow Wyes",
          wye_saddle: "Inline Wye Saddles",
          transition: "Reducers / Stack Boots",
          register_box: "Register Boxes / Grille Transitions",
          register_box_saddle: "Register Box Saddles",
          wall_vent: "Exterior Appliance Wall Vents",
          fresh_air_vent: "Fresh Air Intake Vents",
          end_cover: "End Covers"
        }

        availability_rows = catalog_size_rows(model).map do |row|
          dims = row[:dimensions]
          is_current = current && dimensions_signature(current) == dimensions_signature(dims)
          has_elbow = !Array(row[:elbows]).empty?
          css = [is_current ? "current-row" : nil, has_elbow ? nil : "straight-only"].compact.join(" ")
          branch = (Array(row[:tees]) + Array(row[:tee_saddles]) + Array(row[:wyes]) + Array(row[:wye_saddles])).map(&:sku)
          vents = (
            Array(row[:register_boxes]) + Array(row[:register_saddles]) +
            Array(row[:wall_vents]) + Array(row[:fresh_air_vents]) + Array(row[:covers])
          ).map(&:sku)
          <<~ROW
            <tr class="#{css}">
              <td><b>#{html_escape(dimensions_label(dims))}</b></td>
              <td>#{html_escape(Array(row[:pipes]).map(&:sku).join(', '))}</td>
              <td>#{html_escape(Array(row[:elbows]).map(&:sku).join(', ').yield_self { |x| x.empty? ? 'NONE' : x })}</td>
              <td>#{html_escape(branch.join(', ').yield_self { |x| x.empty? ? '—' : x })}</td>
              <td>#{html_escape(Array(row[:transitions]).map(&:sku).join(', ').yield_self { |x| x.empty? ? '—' : x })}</td>
              <td>#{html_escape(vents.join(', ').yield_self { |x| x.empty? ? '—' : x })}</td>
              <td><b>#{has_elbow ? 'TURNABLE' : 'STRAIGHT ONLY'}</b></td>
            </tr>
          ROW
        end.join

        details = family_names.map do |family, heading|
          products = Array(groups[family]).sort_by { |p| [p.shape.to_s, p.diameter.to_f, p.width.to_f, p.sku.to_s] }
          next "" if products.empty?
          body = products.map do |product|
            compatible = current ? compatible_products(current, model).include?(product) : false
            klass = compatible ? "compatible" : ""
            "<tr class='#{klass}'><td><b>#{html_escape(product.sku)}</b></td><td>#{html_escape(product.name)}</td><td>#{html_escape(product_connector_text(product))}</td><td>#{html_escape(product_envelope_text(product))}</td></tr>"
          end.join
          "<section><h2>#{heading}</h2><table><thead><tr><th>Model</th><th>Product</th><th>Catalog connections / size</th><th>Loaded physical envelope</th></tr></thead><tbody>#{body}</tbody></table></section>"
        end.join

        current_html = if current
          "<div class='current'><b>Current duct:</b> #{html_escape(dimensions_label(current))}. Matching products are highlighted.</div>"
        else
          "<div class='current'>Buildability now includes full-flow end junctions, inline saddle takeoffs, register/grille transitions, exterior wall vents, and end covers.</div>"
        end

        <<~HTML
          <!doctype html><html><head><meta charset="utf-8"><style>
          body{font-family:Arial,sans-serif;margin:18px;color:#222;background:#fafafa}
          h1{margin:0 0 8px;font-size:24px} h2{font-size:18px;margin-top:28px;border-bottom:1px solid #bbb;padding-bottom:5px}
          .current{background:#eef5ff;border:1px solid #9bbce6;padding:10px 12px;border-radius:6px;margin:14px 0}
          .note{font-size:13px;color:#555;margin-bottom:14px}.warning{background:#fff2d9;border:1px solid #e0aa55;padding:9px 11px;border-radius:5px;margin:12px 0}
          table{border-collapse:collapse;width:100%;background:white} th,td{border:1px solid #ddd;padding:7px;text-align:left;vertical-align:top}
          th{background:#eee;position:sticky;top:0}.compatible,.current-row{background:#e8f7e8}.straight-only{background:#fff0f0}.current-row.straight-only{background:#ffe6cc}
          </style></head><body>
          <h1>Master Flow — Simple Duct catalog</h1>
          <div class="note">Straight duct is grouped by connector size/style and modeled continuously from the start and end you choose; no intermediate circumference lines are drawn. Inline Add Tee uses TS6 where compatible, and Add Wye Saddle uses 45YS4 on an equal-or-larger round main. Compatible register boxes, appliance wall vents, screened fresh-air vents, and end caps are offered through Add Vent.</div>
          #{current_html}
          <div class="warning"><b>Catalog truthfulness:</b> full-flow tees/wyes and side saddles are different product families. Simple Duct now keeps those placement behaviors separate.</div>
          <h2>Buildability by duct size</h2>
          <table><thead><tr><th>Duct size</th><th>Straight SKU(s)</th><th>Elbow(s)</th><th>Branches / Saddles</th><th>Transitions</th><th>Vents / Ends</th><th>Routing</th></tr></thead><tbody>#{availability_rows}</tbody></table>
          #{details}
          </body></html>
        HTML
      end

      def product_connector_text(product)
        case product.family
        when :pipe
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" round; continuous model run"
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\"; continuous model run"
          end
        when :elbow
          product.shape.to_sym == :round ? "#{number_label(product.diameter)}\" round, adjustable through 90°" : "#{number_label(product.width)}\" × #{number_label(product.height)}\", fixed 90°"
        when :tee
          "#{number_label(product.diameter)}\" full-flow 90° tee"
        when :tee_saddle
          "#{number_label(product.diameter)}\" main × #{number_label(product.branch_diameter)}\" branch, 90° saddle"
        when :wye
          outlet = product.outlet_diameter || product.branch_diameter || product.diameter
          "#{number_label(product.diameter)}\" inlet → #{number_label(outlet)}\" + #{number_label(outlet)}\""
        when :wye_saddle
          "#{number_label(product.branch_diameter)}\" 45° branch on equal/larger round main"
        when :register_box
          "#{number_label(product.diameter)}\" round → #{number_label(product.width)}\" × #{number_label(product.height)}\" register opening"
        when :register_box_saddle
          "#{number_label(product.diameter)}\" round side saddle → #{number_label(product.width)}\" × #{number_label(product.height)}\" opening"
        when :wall_vent
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" round terminal"
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\" rectangular terminal"
          end
        when :fresh_air_vent
          "#{number_label(product.diameter)}\" round screened intake terminal"
        when :transition
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" ↔ #{number_label(product.branch_diameter)}\""
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\" ↔ #{number_label(product.diameter)}\" round"
          end
        when :end_cover
          product.shape.to_sym == :round ? "#{number_label(product.diameter)}\" round" : "#{number_label(product.width)}\" × #{number_label(product.height)}\""
        else
          ""
        end
      end
    end
  end
end

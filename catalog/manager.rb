module DuctExtension
  module Catalog
    module Manager
      DICTIONARY = "DuctExtensionCatalog"
      ACTIVE_KEY = "active_catalog"
      BASE_KEY = :base
      MASTER_FLOW_KEY = :master_flow
      TOLERANCE = 0.01

      module_function

      def active_key(model = nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        return BASE_KEY unless model

        text = model.get_attribute(DICTIONARY, ACTIVE_KEY, BASE_KEY.to_s).to_s
        text == MASTER_FLOW_KEY.to_s ? MASTER_FLOW_KEY : BASE_KEY
      rescue
        BASE_KEY
      end

      def active?(model = nil)
        active_key(model) != BASE_KEY
      end

      def active_name(model = nil)
        active_key(model) == MASTER_FLOW_KEY ? MasterFlow::NAME : "Base / Generic"
      end

      def set_active(model, key)
        return false unless model

        normalized = key.to_s.downcase.include?("master") ? MASTER_FLOW_KEY : BASE_KEY
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
          ["Base / Generic|Master Flow"],
          "Set Duct Catalog"
        )
        return nil unless input

        key = set_active(model, input[0])
        return nil unless key

        message =
          if key == MASTER_FLOW_KEY
            "Master Flow catalog enabled. New duct pieces will be restricted to supported Master Flow products."
          else
            "Catalog cleared. New pieces will use the extension's base/generic geometry and free-form sizes."
          end

        Sketchup.status_text = message if defined?(Sketchup)
        ::UI.messagebox(message)
        key
      rescue => error
        puts "Catalog::Manager.prompt_set_catalog failed: #{error.message}"
        nil
      end

      def all_products(model = nil)
        active_key(model) == MASTER_FLOW_KEY ? MasterFlow.products : []
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

      def elbow_bend_radius(product, dimensions, fallback)
        return fallback.to_f unless product && product.overall
        dims = Model::DuctDimensions.coerce(dimensions)

        if dims.round?
          value = product.overall[:derived_centerline_radius]
          return value.to_f if value && value.to_f > 0.0
        elsif dims.rectangular?
          # The published envelope constrains a simple procedural approximation.
          # Short-way and long-way variants therefore produce visibly different
          # bend radii while keeping the existing rectangular elbow implementation.
          h = product.overall[:height].to_f
          smallest = [dims.width, dims.height].min
          value = h - smallest / 2.0
          return value if value > 0.0
        end

        fallback.to_f
      rescue
        fallback.to_f
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
          "Master Flow Duct Settings"
        )
        return nil unless shape_input

        shape = shape_input[0].to_s.downcase.start_with?("rect") ? :rectangular : :round
        products = pipe_products(shape, model)
        if products.empty?
          ::UI.messagebox("No supported Master Flow #{shape} straight-duct products are loaded in this pilot catalog.")
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
          "Master Flow Duct Product"
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
            "Master Flow Routing Product"
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
            "Master Flow Routing Product"
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
          ::UI.messagebox("Master Flow has no supported #{family} for this duct size in the pilot catalog.")
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
          ::UI.messagebox("There is no supported Master Flow reducer/stack-boot transition from this size in the pilot catalog.")
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

        group.set_attribute(DICTIONARY, "catalog_key", MASTER_FLOW_KEY.to_s)
        group.set_attribute(DICTIONARY, "catalog_name", MasterFlow::NAME)
        group.set_attribute(DICTIONARY, "model_number", product.sku.to_s)
        group.set_attribute(DICTIONARY, "product_name", product.name.to_s)
        group.set_attribute(DICTIONARY, "family", product.family.to_s)
        group.set_attribute(DICTIONARY, "nominal_shape", product.shape.to_s)
        group.set_attribute(DICTIONARY, "nominal_diameter", product.diameter.to_f) if product.diameter
        group.set_attribute(DICTIONARY, "nominal_width", product.width.to_f) if product.width
        group.set_attribute(DICTIONARY, "nominal_height", product.height.to_f) if product.height
        group.set_attribute(DICTIONARY, "branch_diameter", product.branch_diameter.to_f) if product.branch_diameter
        group.set_attribute(DICTIONARY, "stock_length", product.stock_length.to_f) if product.stock_length
        group.set_attribute(DICTIONARY, "catalog_document", MasterFlow::CATALOG_DOCUMENT)

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
        "Master Flow catalog mode has no supported #{family.to_s.tr('_', ' ')}#{detail} in this pilot. No generic fitting was created."
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

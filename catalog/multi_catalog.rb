module DuctExtension
  module Catalog
    module Manager
      module_function

      def prompt_terminal_product(dimensions, model = nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        products =
          end_cover_products(dimensions, model) +
          register_box_products(dimensions, model) +
          wall_vent_products(dimensions, model) +
          fresh_air_vent_products(dimensions, model)
        prompt_product_from(products, title: "#{active_name(model)} End Component", label: "End Product:")
      end

      def prompt_register_box_saddle(dimensions, model = nil)
        model ||= Sketchup.active_model if defined?(Sketchup)
        prompt_product_from(
          register_box_saddle_products(dimensions, model),
          title: "#{active_name(model)} Side Register",
          label: "Register Saddle:"
        )
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
        lines = ["#{active_name(model)} options for #{dimensions_label(dims)}:"]
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
        catalog_name = active_name(model)
        catalog = active_catalog(model)
        document = catalog ? catalog::CATALOG_DOCUMENT : ""
        groups = products_grouped_by_family(model)
        family_names = {
          pipe: "Straight Duct",
          elbow: "Elbows",
          tee: "Full-Flow Tees",
          tee_saddle: "Inline Tee Saddles",
          wye: "Full-Flow Wyes",
          wye_saddle: "Inline Wye Saddles",
          transition: "Reducers / Converters",
          register_box: "Register Boxes / Grille Transitions",
          register_box_saddle: "Register Box Saddles",
          wall_vent: "Exterior Wall Vents",
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
          "<div class='current'>Buildability includes only product families that map cleanly onto Simple Duct's existing duct/fitting semantics.</div>"
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
          <h1>#{html_escape(catalog_name)} — Simple Duct catalog</h1>
          <div class="note">Source catalog: #{html_escape(document)}. Packaged straight-duct lengths/gauges are collapsed to one representative real SKU per connector size so modeling remains continuous. Unsupported specialty families are intentionally omitted rather than approximated as generic parts.</div>
          #{current_html}
          <div class="warning"><b>Catalog truthfulness:</b> a missing product is treated as unavailable. Simple Duct does not silently substitute a generic fitting while a manufacturer catalog is active.</div>
          <h2>Buildability by duct size</h2>
          <table><thead><tr><th>Duct size</th><th>Straight SKU(s)</th><th>Elbow(s)</th><th>Branches / Saddles</th><th>Transitions</th><th>Vents / Ends</th><th>Routing</th></tr></thead><tbody>#{availability_rows}</tbody></table>
          #{details}
          </body></html>
        HTML
      end

      def product_connector_text(product)
        case product.family
        when :pipe
          product.shape.to_sym == :round ?
            "#{number_label(product.diameter)}\" round; continuous model run" :
            "#{number_label(product.width)}\" × #{number_label(product.height)}\"; continuous model run"
        when :elbow
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" round, adjustable through #{number_label(product.angle_degrees || 90)}°"
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\", fixed #{number_label(product.angle_degrees || 90)}°"
          end
        when :tee
          "#{number_label(product.diameter)}\" full-flow 90° tee"
        when :tee_saddle
          "#{number_label(product.branch_diameter || product.diameter)}\" 90° branch saddle"
        when :wye
          outlet = product.outlet_diameter || product.diameter
          branch = product.branch_diameter || outlet
          "#{number_label(product.diameter)}\" inlet → #{number_label(outlet)}\" straight + #{number_label(branch)}\" branch"
        when :wye_saddle
          "#{number_label(product.branch_diameter || product.diameter)}\" 45° branch on equal/larger round main"
        when :register_box
          "#{number_label(product.diameter)}\" round → #{number_label(product.width)}\" × #{number_label(product.height)}\" register opening"
        when :register_box_saddle
          "#{number_label(product.diameter)}\" round side saddle → #{number_label(product.width)}\" × #{number_label(product.height)}\" opening"
        when :wall_vent
          product.shape.to_sym == :round ?
            "#{number_label(product.diameter)}\" round terminal" :
            "#{number_label(product.width)}\" × #{number_label(product.height)}\" rectangular terminal"
        when :fresh_air_vent
          "#{number_label(product.diameter)}\" round screened intake terminal"
        when :transition
          if product.shape.to_sym == :round
            "#{number_label(product.diameter)}\" ↔ #{number_label(product.branch_diameter)}\""
          else
            "#{number_label(product.width)}\" × #{number_label(product.height)}\" ↔ #{number_label(product.diameter)}\" round"
          end
        when :end_cover
          product.shape.to_sym == :round ?
            "#{number_label(product.diameter)}\" round" :
            "#{number_label(product.width)}\" × #{number_label(product.height)}\""
        else
          ""
        end
      end
    end
  end
end

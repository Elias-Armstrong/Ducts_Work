# ===== Consolidated from: ui/actions.rb =====
module DuctExtension
  module UIActions
    module_function

    def set_catalog
      Catalog::Manager.prompt_set_catalog(Sketchup.active_model)
    end

    def browse_catalog
      model = Sketchup.active_model
      unless Catalog::Manager.active?(model)
        ::UI.messagebox("Base / Generic mode is active. Choose Master Flow from Set Catalog... first.")
        return false
      end

      Catalog::Manager.show_catalog_browser(model)
    end

    def current_catalog_options
      model = Sketchup.active_model
      unless Catalog::Manager.active?(model)
        ::UI.messagebox("Catalog availability applies only when a product catalog is active.")
        return false
      end

      dimensions = selected_piece_dimensions(model)
      Catalog::Manager.show_catalog_browser(model, dimensions: dimensions)
    end

    # In the proven P8 tool baseline, the catalog straight/elbow selector is the
    # normal DuctTool setup dialog. Re-entering the tool is therefore the safest
    # way to choose the current stocked straight and elbow products without
    # changing the right-click callback path.
    def choose_catalog_products
      model = Sketchup.active_model
      unless Catalog::Manager.active?(model)
        ::UI.messagebox("Choose Master Flow from Set Catalog... before selecting stocked products.")
        return false
      end

      model.select_tool(Tool::DuctTool.new)
      true
    rescue => error
      puts "UIActions.choose_catalog_products failed: #{error.message}"
      false
    end

    def draw_duct
      Sketchup.active_model.select_tool(Tool::DuctTool.new)
    end

    def resize_selection
      model = Sketchup.active_model
      Services::SelectionResizeService.run(
        model: model,
        network: DuctExtension.network_for_model(model)
      )
    end

    def add_reducer
      Sketchup.active_model.select_tool(Tool::ReducerTool.new)
    end

    def clear_duct_data
      result = ::UI.messagebox(
        "This will clear all stored duct connection data from this model for performance purposes.\n\n" \
        "The 3D duct geometry will remain unchanged, but old ducts will no longer snap as editable duct pieces.\n\n" \
        "Continue?",
        MB_YESNO
      )
      return false unless result == IDYES

      model = Sketchup.active_model
      Services::NetworkClearService.clear_model_data(
        model,
        DuctExtension.network_for_model(model)
      )
      ::UI.messagebox("Duct data cleared. Geometry was left unchanged.")
      true
    end

    def selected_piece_dimensions(model)
      network = Services::NetworkRebuildService.rebuild(model)
      selected_groups = model.selection.to_a
      piece = network.pieces.find do |candidate|
        candidate && candidate.group && selected_groups.include?(candidate.group)
      end
      port = piece && piece.ports && piece.ports.first
      port ? Model::Port.dimensions_from_params({}, port) : nil
    rescue => error
      puts "UIActions.selected_piece_dimensions failed: #{error.message}"
      nil
    end
  end
end

# ===== Consolidated from: ui/toolbar.rb =====
module DuctExtension
  module Toolbar
    TOOLBAR_NAME = "Simple Duct"

    def self.create
      return if @created

      toolbar = UI::Toolbar.new(TOOLBAR_NAME)

      draw_command = UI::Command.new("Draw Orthogonal Duct") { UIActions.draw_duct }
      draw_command.tooltip = "Draw Orthogonal Duct"
      draw_command.status_bar_text = "Draw round or rectangular duct using orthogonal snap routing."

      browse_command = UI::Command.new("Browse Catalog") { UIActions.browse_catalog }
      browse_command.tooltip = "Browse Catalog"
      browse_command.status_bar_text = "Show Master Flow buildability by duct size and the supported stocked products."

      resize_command = UI::Command.new("Resize Selected Duct Pieces") { UIActions.resize_selection }
      resize_command.tooltip = "Resize Selected Duct Pieces"
      resize_command.status_bar_text = "Resize selected generic duct pieces and add boundary reducers/increasers where needed."

      reducer_command = UI::Command.new("Add Increaser / Reducer") { UIActions.add_reducer }
      reducer_command.tooltip = "Add Increaser / Reducer"
      reducer_command.status_bar_text = "Click an open duct end and enter the new size."

      clear_command = UI::Command.new("Clear Duct Data") { UIActions.clear_duct_data }
      clear_command.tooltip = "Clear Duct Data"
      clear_command.status_bar_text = "Clear duct metadata while leaving geometry in place."

      [draw_command, browse_command, resize_command, reducer_command, clear_command].each do |command|
        toolbar.add_item(command)
      end
      toolbar.restore

      @created = true
      toolbar
    rescue => error
      puts "DuctExtension::Toolbar.create failed: #{error.message}"
      nil
    end
  end
end

# ===== Consolidated from: ui/actions.rb =====
module DuctExtension
  module UIActions
    module_function

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

      resize_command = UI::Command.new("Resize Selected Duct Pieces") { UIActions.resize_selection }
      resize_command.tooltip = "Resize Selected Duct Pieces"
      resize_command.status_bar_text = "Resize selected duct pieces and add boundary reducers/increasers where needed."

      reducer_command = UI::Command.new("Add Increaser / Reducer") { UIActions.add_reducer }
      reducer_command.tooltip = "Add Increaser / Reducer"
      reducer_command.status_bar_text = "Click an open duct end and enter the new size."

      clear_command = UI::Command.new("Clear Duct Data") { UIActions.clear_duct_data }
      clear_command.tooltip = "Clear Duct Data"
      clear_command.status_bar_text = "Clear duct metadata while leaving geometry in place."

      [draw_command, resize_command, reducer_command, clear_command].each { |command| toolbar.add_item(command) }
      toolbar.restore

      @created = true
      toolbar
    rescue => error
      puts "DuctExtension::Toolbar.create failed: #{error.message}"
      nil
    end
  end
end

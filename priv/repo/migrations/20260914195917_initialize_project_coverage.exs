defmodule QuickTrain.Repo.Migrations.InitializeProjectCoverage do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO task_item_coverage (organization_id, project_id, form_version_id, project_item_id, exposures)
    SELECT project.organization_id, project.id, project.form_version_id, item.id, count(input.id)
    FROM projects AS project JOIN project_items AS item ON item.project_id = project.id
    LEFT JOIN task_inputs AS input ON input.project_item_id = item.id
    WHERE project.state <> 'draft'
    GROUP BY project.organization_id, project.id, project.form_version_id, item.id
    ON CONFLICT (project_item_id) DO NOTHING
    """)
  end

  # These rows are valid for the previous allocator as well; rollback retains them.
  def down, do: :ok
end

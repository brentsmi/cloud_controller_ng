module VCAP::CloudController::Models
  class ServicePlanVisibility < Sequel::Model
    many_to_one :service_plan
    many_to_one :organization

    import_attributes :service_plan_guid, :organization_guid
    export_attributes :service_plan_guid, :organization_guid

    def validate
      validates_presence :service_plan
      validates_presence :organization
      validates_unique [:organization_id, :service_plan_id]
    end

    def self.visible_private_plan_ids_for_user(user)
      user.organizations.map {|org| 
        visible_private_plan_ids_for_organization(org)
      }.flatten.uniq
    end

    def self.visible_private_plan_ids_for_organization(organization)
      organization.service_plan_visibilities.map { |visibility| visibility.service_plan_id }
    end

    def self.user_visibility_filter(user)
      user_visibility_filter_with_admin_override(id: []) # awful hack: non-admins see no records
    end
  end
end

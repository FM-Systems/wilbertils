# Schema for the nulldb connection in spec_helper_lite. nulldb stores no data;
# only the column definitions matter.
ActiveRecord::Schema.define do
  create_table :localities, force: true do |t|
    t.string  :postcode
    t.string  :sublocality
    t.string  :locality
    t.string  :region
    t.string  :country
    t.decimal :longitude
    t.decimal :latitude
    t.string  :locality_type
    t.string  :timezone
  end

  create_table :widgets, force: true do |t|
  end
end

require 'active_model_serializers/adapter/json_api_pg'
require 'active_model_serializers_pg/collection_serializer'

# We have to inject our own CollectionSerializer to avoid materializing ActiveRecord::Relations.
# See more detailed notes in our class:
ActiveModel::Serializer.config.collection_serializer = ActiveModelSerializersPg::CollectionSerializer

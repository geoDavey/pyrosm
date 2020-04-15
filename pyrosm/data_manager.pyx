from pyrosm.data_filter cimport filter_osm, filter_array_dict_by_indices_or_mask, filter_relation_indices
from pyrosm._arrays cimport convert_to_arrays_and_drop_empty, convert_way_records_to_lists, concatenate_dicts_of_arrays
import numpy as np

cdef get_data_filter_and_osm_keys(custom_filter):
    osm_keys = []
    if isinstance(custom_filter, dict):
        data_filter = {}
        for key, tags in custom_filter.items():
            if not isinstance(key, str):
                raise ValueError(f"OSM key of the 'custom_filter' "
                                 f"should be text. "
                                 f"Got: {key} with type {type(key)}.")
            osm_keys.append(key)

            # If osm-key has been defined as True,
            # all tags should be kept, hence, no further filtering
            # should be done.
            if tags == True:
                continue

            elif isinstance(tags, list):
                # Check that all values used for filtering are text (except None).
                # Even numeric data should be passed as string.
                for tag in tags:
                    if tag is None:
                        continue
                    if not isinstance(tag, str):
                        raise ValueError(f"OSM tag of the 'custom_filter' "
                                         f"should be text. "
                                         f"Got: {tag} with type {type(tag)}.")
            elif isinstance(tags, str):
                tags = [tags]

            data_filter[key] = tags
        return data_filter, osm_keys
    else:
        raise ValueError(f"'custom_filter' should be a Python dictionary. "
                         f"Got {custom_filter} with type {type(custom_filter)}.")


cdef get_relation_arrays(relations, osm_keys, data_filter):
    # Combine all blocks
    relations = concatenate_dicts_of_arrays(relations)
    # Get indices for MultiPolygons that also passes data_filter
    indices = filter_relation_indices(relations, osm_keys, data_filter)
    # If no building relations were found, return None
    if len(indices) == 0:
        return None
    # Otherwise, filter the data accordingly
    return filter_array_dict_by_indices_or_mask(relations, indices)

cdef separate_relation_ways(way_records, relation_way_ids):
    cdef int i, n = len(way_records)
    # Create lookup dict
    relation_ids = dict.fromkeys(relation_way_ids, None)
    normal_ways = []
    relation_ways = []
    for i in range(0, n):
        way = way_records[i]
        try:
            # Check if way is part of relation
            relation_ids[way["id"]]
            relation_ways.append(way)
        except Exception as e:
            normal_ways.append(way)
    return normal_ways, relation_ways

cdef get_way_arrays(way_records, relation_way_ids, osm_keys, tags_as_columns, data_filter, filter_type):
    # Get all ways including the ones associated with relations
    ways = filter_osm(way_records,
                      data_filter,
                      osm_keys,
                      relation_way_ids,
                      filter_type)

    # If there is not data in the area, do not continue
    # (return None for ways and relations)
    if len(ways) == 0:
        return None, None

    relation_arrays = None
    if relation_way_ids is not None:
        # Separate ways that are part of a relation
        ways, relation_ways = separate_relation_ways(ways, relation_way_ids)
        relation_ways = convert_way_records_to_lists(relation_ways, tags_as_columns)
        relation_arrays = convert_to_arrays_and_drop_empty(relation_ways)

    # Process separated ways
    ways = convert_way_records_to_lists(ways, tags_as_columns)
    way_arrays = convert_to_arrays_and_drop_empty(ways)

    return way_arrays, relation_arrays

cdef get_osm_ways_and_relations(way_records, relations, osm_keys, tags_as_columns, data_filter, filter_type):

    # Tags that should always be kept
    tags_as_columns += ["id", "nodes", "timestamp", "version"]

    # Get relations for specified OSM keys (one or multiple)
    if relations is not None:
        filtered_relations = get_relation_arrays(relations, osm_keys, data_filter)

        # Get all way-ids that are associated with relations
        relation_way_ids = None
        if filtered_relations is not None:
            members = concatenate_dicts_of_arrays(filtered_relations['members'])
            relation_way_ids = members["member_id"]

            if type(relation_way_ids) not in [list, np.ndarray]:
                raise ValueError("'relation_way_ids' should be a list or an array.")
    else:
        relation_way_ids = None
        filtered_relations = None

    # Get ways (separately as "normal" ways and relation_ways)
    ways, relation_ways = get_way_arrays(way_records,
                                         relation_way_ids,
                                         osm_keys,
                                         tags_as_columns,
                                         data_filter,
                                         filter_type)

    # If there weren't any ways return None
    if ways is None:
        return None, None, None

    return ways, relation_ways, filtered_relations

cdef _get_osm_data(way_records, relations, tags_as_columns, data_filter, filter_type, osm_keys):
    if osm_keys is None:
        # Convert filter to appropriate form and parse keys
        data_filter, osm_keys = get_data_filter_and_osm_keys(data_filter)

    # Parse ways and relations
    ways, relation_ways, filtered_relations = get_osm_ways_and_relations(way_records, relations, osm_keys, tags_as_columns, data_filter, filter_type)
    return ways, relation_ways, filtered_relations

cpdef get_osm_data(way_records, relations, tags_as_columns, data_filter, filter_type, osm_keys=None):
    return _get_osm_data(way_records, relations, tags_as_columns, data_filter, filter_type, osm_keys)

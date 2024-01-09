#include <css/StyleCache.h>
#include <css/Property.h>
#include <assert.h>
#include <array>
#include <vector>
extern "C" {
#include <style.h>
}

constexpr inline style_handle_t STYLE_NULL = {0};

namespace Rml::Style {
    void TableRef::AddRef() {
        if (idx == 0) {
            return;
        }
        Instance().TableAddRef(*this);
    }

    void TableRef::Release() {
        if (idx == 0) {
            return;
        }
        Instance().TableRelease(*this);
    }

    Cache::Cache(const PropertyIdSet& inherit) {
        uint8_t inherit_mask[128] = {0};
        for (auto id : inherit) {
            inherit_mask[(size_t)id] = 1;
        }
        c = style_newcache(inherit_mask, NULL, NULL);
        assert(c);
    }

    Cache::~Cache() {
        style_deletecache(c);
    }

    TableValue Cache::Create() {
        style_handle_t s = style_create(c, 0, NULL);
        return {s.idx};
    }

    TableValue Cache::Create(const PropertyVector& vec) {
        style_handle_t s = style_create(c, (int)vec.size(), (int*)vec.data());
        return {s.idx};
    }

    TableCombination Cache::Merge(const std::span<TableValue>& maps) {
        if (maps.empty()) {
            style_handle_t s = style_null(c);
            return {s.idx};
        }
        style_handle_t s = {maps[0].idx};
        for (size_t i = 1; i < maps.size(); ++i) {
            s = style_inherit(c, s, {maps[i].idx}, 0);
        }
        return {s.idx};
    }

    TableCombination Cache::Merge(TableValue A, TableValue B, TableValue C) {
        style_handle_t s = style_inherit(c, {A.idx}, style_inherit(c, {B.idx}, {C.idx}, 0), 0);
        style_addref(c, s);
        return {s.idx};
    }

    TableCombination Cache::Inherit(TableCombination child, TableCombination parent) {
        style_handle_t s = style_inherit(c, {child.idx}, {parent.idx}, 1);
        style_addref(c, s);
        return {s.idx};
    }

    TableCombination Cache::Inherit(TableCombination child) {
        style_addref(c, {child.idx});
        return {child.idx};
    }

    bool Cache::Assgin(TableValue to, TableCombination from) {
        return 0 != style_assign(c, {to.idx}, {from.idx});
    }

    bool Cache::Compare(TableValue a, TableCombination b) {
        return 0 != style_compare(c, {a.idx}, {b.idx});
    }

    void Cache::Clone(TableValue to, TableValue from) {
        style_assign(c, {to.idx}, {from.idx});
    }

    void Cache::Release(TableValueOrCombination s) {
        style_release(c, {s.idx});
    }

    bool Cache::SetProperty(TableValue s, PropertyId id, const Property& prop) {
        int attrib_id = prop.RawAttribId();
        return !!style_modify(c, {s.idx}, 1, &attrib_id, 0, nullptr);
    }

    bool Cache::DelProperty(TableValue s, PropertyId id) {
        int removed_key[1] = { (int)(uint8_t)id };
        return !!style_modify(c, {s.idx}, 0, nullptr, 1, removed_key);
    }

    PropertyIdSet Cache::SetProperty(TableValue s, const PropertyVector& vec) {
        std::vector<int> attrib_id(vec.size());
        size_t i = 0;
        for (auto const& v : vec) {
            attrib_id[i] = v.RawAttribId();
            i++;
        }
        if (!style_modify(c, {s.idx}, (int)attrib_id.size(), attrib_id.data(), 0, nullptr)) {
            return {};
        }
        PropertyIdSet change;
        for (size_t i = 0; i < attrib_id.size(); ++i) {
            if (attrib_id[i]) {
                change.insert(GetPropertyId(vec[i]));
            }
        }
        return change;
    }

    PropertyIdSet Cache::DelProperty(TableValue s, const PropertyIdSet& set) {
        std::vector<int> removed_key(set.size());
        size_t i = 0;
        for (auto id : set) {
            removed_key[i] = (int)(uint8_t)id;
            i++;
        }
        if (!style_modify(c, {s.idx}, 0, nullptr, (int)removed_key.size(), removed_key.data())) {
            return {};
        }
        PropertyIdSet change;
        i = 0;
        for (auto id : set) {
            if (removed_key[i]) {
                change.insert(id);
            }
            i++;
        }
        return change;
    }

    Property Cache::Find(TableValueOrCombination s, PropertyId id) {
        int attrib_id = style_find(c, {s.idx}, (uint8_t)id);
        return { attrib_id };
    }

    bool Cache::Has(TableValueOrCombination s, PropertyId id) {
        int attrib_id = style_find(c, {s.idx}, (uint8_t)id);
        return attrib_id != -1;
    }

    void Cache::Foreach(TableValueOrCombination s, PropertyIdSet& set) {
        for (int i = 0;; ++i) {
            int attrib_id = style_index(c, {s.idx}, i);
            if (attrib_id == -1) {
                break;
            }
            style_attrib attrib;
            style_attrib_value(c, attrib_id, &attrib);
            set.insert((PropertyId)attrib.key);
        }
    }

    void Cache::Foreach(TableValueOrCombination s, PropertyUnit unit, PropertyIdSet& set) {
        for (int i = 0;; ++i) {
            Property prop { style_index(c, {s.idx}, i) };
            if (!prop) {
                break;
            }
            if (prop.IsFloatUnit(unit)) {
                set.insert(GetPropertyId(prop));
            }
        }
    }

    static auto Fetch(style_cache* c, TableValueOrCombination t) {
        std::array<int, (size_t)EnumCountV<PropertyId>> datas;
        datas.fill(-1);
        for (int i = 0;; ++i) {
            int attrib_id = style_index(c, {t.idx}, i);
            if (attrib_id == -1) {
                break;
            }
            style_attrib attrib;
            style_attrib_value(c, attrib_id, &attrib);
            datas[(size_t)attrib.key] = attrib_id;
        }
        return datas;
    }

    PropertyIdSet Cache::Diff(TableValueOrCombination a, TableValueOrCombination b) {
        PropertyIdSet ids;
        auto a_datas = Fetch(c, a);
        auto b_datas = Fetch(c, b);
        for (size_t i = 0; i < (size_t)EnumCountV<PropertyId>; ++i) {
            if (a_datas[i] != b_datas[i]) {
                ids.insert((PropertyId)i);
            }
        }
        return ids;
    }

    void Cache::Flush() {
        style_flush(c);
    }

    Property Cache::CreateProperty(PropertyId id, std::span<uint8_t> value) {
        style_attrib v;
        v.key = (uint8_t)id;
        v.data = (void*)value.data();
        v.sz = value.size();
        int attrib_id = style_attrib_id(c, &v);
        return { attrib_id };
    }
        
    PropertyId Cache::GetPropertyId(Property prop) {
        style_attrib v;
        style_attrib_value(c, prop.RawAttribId(), &v);
        return (PropertyId)v.key;
    }

    std::span<const std::byte> Cache::GetPropertyData(Property prop) {
        style_attrib v;
        style_attrib_value(c, prop.RawAttribId(), &v);
        return { (const std::byte*)v.data, v.sz };
    }

    void Cache::PropertyAddRef(Property prop) {
        style_attrib_addref(c, prop.RawAttribId());
    }

    void Cache::PropertyRelease(Property prop) {
        style_attrib_release(c, prop.RawAttribId());
    }

    void Cache::TableAddRef(TableValueOrCombination s) {
        style_addref(c, { s.idx });
    }

    void Cache::TableRelease(TableValueOrCombination s) {
        style_release(c, { s.idx });
    }

    static Cache* cahce = nullptr;

    void Initialise(const PropertyIdSet& inherit) {
        assert(!cahce);
        cahce = new Cache(inherit);
    }

    void Shutdown() {
        delete cahce;
    }

    Cache& Instance() {
        return *cahce;
    }
}

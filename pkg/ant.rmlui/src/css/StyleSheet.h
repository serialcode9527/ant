#pragma once

#include <core/ID.h>
#include <css/PropertyVector.h>
#include <css/StyleCache.h>
#include <unordered_map>
#include <vector>

namespace Rml {

class Element;
class StyleSheetNode;

struct AnimationKey {
	AnimationKey(float time, PropertyId id, const Property& value)
		: time(time)
		, prop { id, value } {
		prop.AddRef();
	}
	AnimationKey(AnimationKey&& rhs)
		: time(rhs.time)
		, prop(rhs.prop) {
		rhs.prop = {};
	}
	AnimationKey(const AnimationKey& rhs)
		: time(rhs.time)
		, prop(rhs.prop) {
		prop.AddRef();
	}
	AnimationKey& operator=(AnimationKey&& rhs) {
		if (this != &rhs) {
			time = rhs.time;
			prop = rhs.prop;
			rhs.prop = {};
		}
		return *this;
	}
	AnimationKey& operator=(const AnimationKey& rhs) {
		if (this != &rhs) {
			time = rhs.time;
			prop = rhs.prop;
			prop.AddRef();
		}
		return *this;
	}
	~AnimationKey() {
		prop.Release();
	}
	float time;
	PropertyView prop;
};

using Keyframe = std::vector<AnimationKey>;
using Keyframes = std::map<PropertyId, Keyframe>;

class StyleSheet {
public:
	StyleSheet();
	~StyleSheet();
	StyleSheet(const StyleSheet&) = delete;
	StyleSheet& operator=(const StyleSheet&) = delete;
	void Merge(const StyleSheet& sheet);
	void AddNode(StyleSheetNode && node);
	void AddKeyframe(const std::string& identifier, const std::vector<float>& rule_values, const PropertyVector& properties);
	void Sort();
	const Keyframes* GetKeyframes(const std::string& name) const;
	Style::TableCombination GetElementDefinition(const Element* element) const;

private:
	std::vector<StyleSheetNode> stylenode;
	std::unordered_map<std::string, Keyframes> keyframes;
};

}

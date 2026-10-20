// stellar_native: the C++ kernels of Stellar Defense (docs/PERF_NATIVE.md).
#include "register_types.h"

#include "stellar_arena_nav.h"
#include "stellar_monster_pose.h"
#include "stellar_roads.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_stellar_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(StellarRoads);
	GDREGISTER_CLASS(StellarArenaNav);
	GDREGISTER_CLASS(StellarMonsterPose);
}

void uninitialize_stellar_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT stellar_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_stellar_native);
	init_obj.register_terminator(uninitialize_stellar_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}

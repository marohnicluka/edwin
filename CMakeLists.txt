cmake_minimum_required(VERSION 2.8)
cmake_policy(VERSION 2.8)
project(edwin)
include(GNUInstallDirs)

set(EXEC_NAME "edwin")
set(RELEASE_NAME "Simple Document Writer for elementary OS.")
set(VERSION "0.1")
set(VERSION_INFO "alpha")
set(GETTEXT_PACKAGE ${EXEC_NAME})
set(DATADIR "${CMAKE_INSTALL_FULL_DATAROOTDIR}")
set(PKGDATADIR "${DATADIR}/${EXEC_NAME}")
set(PREFIX ${CMAKE_INSTALL_PREFIX})
set(DOLLAR "$")
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)

# Add 'make dist' command for creating release tarball
set(CPACK_PACKAGE_VERSION ${VERSION})
set(CPACK_SOURCE_GENERATOR "TGZ")
set(CPACK_SOURCE_PACKAGE_FILE_NAME "${CMAKE_PROJECT_NAME}-${CPACK_PACKAGE_VERSION}")
set(CPACK_SOURCE_IGNORE_FILES "/build/;/.bzr/;/.bzrignore;~$;${CPACK_SOURCE_IGNORE_FILES}")

include(CPack)
add_custom_target(dist COMMAND ${CMAKE_MAKE_PROGRAM} package_source)

# internationalization
add_definitions(-DGETTEXT_PACKAGE=\"${GETTEXT_PACKAGE}\")

# configuration
configure_file(${CMAKE_SOURCE_DIR}/src/config.vala.cmake ${CMAKE_SOURCE_DIR}/src/config.vala)

# Dependencies
set(EDWIN_DEPS
	gobject-2.0
	glib-2.0
	gio-2.0
	gtk+-3.0>=3.10
	gtkspell3-3.0>=3.0
	granite>=0.4
	gee-0.8>=0.18
	libxml-2.0>=2.9
)

# check dependencies
find_package(PkgConfig)
pkg_check_modules(DEPS REQUIRED ${EDWIN_DEPS})
add_definitions(${DEPS_CFLAGS})
link_libraries(${DEPS_LIBRARIES} -lm)
link_directories(${DEPS_LIBRARY_DIRS})

# Vala
find_package(Vala REQUIRED)
include(ValaVersion)
ensure_vala_version("0.34" MINIMUM)
include(ValaPrecompile)

add_definitions(-DVALA_VERSION="${VALA_SHORTVER}")
add_definitions(-w) # Disable gcc warnings

add_subdirectory(src)
add_subdirectory(schemas)

##
set(NORMAL_CFLAGS ${DEPS_CFLAGS} ${LIBSOURCE_CFLAGS} ${GCONF_CFLAGS})
set(NORMAL_LINK_DIRS ${DEPS_LIBRARY_DIRS} ${LIBSOURCE_LIBRARY_DIRS} ${GCONF_LIBRARY_DIRS})
set(NORMAL_LIBRARIES ${DEPS_LIBRARIES} ${LIBSOURCE_LIBRARIES} ${GCONF_LIBRARIES})

add_definitions(${DEPS_CFLAGS} ${LIBSOURCE_CFLAGS} ${GCONF_CFLAGS})
link_libraries(${DEPS_LIBRARIES} ${LIBSOURCE_LIBRARIES} ${GCONF_LIBRARIES})
link_directories(${DEPS_LIBRARY_DIRS} ${LIBSOURCE_LIBRARY_DIRS} ${GCONF_LIBRARY_DIRS})


# Some include paths
include_directories(${CMAKE_BINARY_DIR}/src)


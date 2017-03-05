# Resources
set(GRESOURCE_FILE "${CMAKE_SOURCE_DIR}/edwin.gresources.xml")
set(RESOURCE_C_FILE "${CMAKE_CURRENT_BINARY_DIR}/resources.c")
execute_process(COMMAND
	glib-compile-resources ${GRESOURCE_FILE}
	--sourcedir=${CMAKE_SOURCE_DIR}
	--target=${RESOURCE_C_FILE}
	--generate-source
)

# Compilation
vala_precompile(VALA_C ${EXEC_NAME}
	config.vala
	edwin.vala
	mainwindow.vala
	toolbar.vala
	statusbar.vala
	document.vala
	textview.vala
	papersize.vala
	settings.vala
	utils.vala
PACKAGES
	${EDWIN_DEPS}
	posix
OPTIONS
	--thread
	--target-glib 2.32
	--vapidir=${CMAKE_SOURCE_DIR}/vapi
)

add_executable(${EXEC_NAME} ${VALA_C} ${RESOURCE_C_FILE})

install(TARGETS ${EXEC_NAME} RUNTIME DESTINATION ${CMAKE_INSTALL_FULL_BINDIR})
install(FILES ${CMAKE_SOURCE_DIR}/data/edwin.desktop DESTINATION ${DATADIR}/applications/)


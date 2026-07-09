# Sanity test — xác nhận toolchain + GoogleTest + CTest hoạt động đúng
add_executable(sanity_test sanity_test.cpp)
target_link_libraries(sanity_test PRIVATE gtest_main)

include(GoogleTest)
gtest_discover_tests(sanity_test)

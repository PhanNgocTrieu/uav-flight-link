// Sanity test — Phase 0
// Mục đích duy nhất: xác nhận CMake + GoogleTest + CTest pipeline chạy được
// trước khi bắt đầu viết logic thật ở Phase 1.

#include <gtest/gtest.h>

TEST(Sanity, AlwaysTrue) {
    EXPECT_TRUE(true);
}

TEST(Sanity, BasicArithmeticWorks) {
    EXPECT_EQ(2 + 2, 4);
}

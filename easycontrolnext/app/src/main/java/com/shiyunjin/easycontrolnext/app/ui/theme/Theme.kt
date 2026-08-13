package com.shiyunjin.easycontrolnext.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

val AccentBlue = Color(0xFF3A70FC)
val SoftGrayBg = Color(0xFFF2F3F5)
val Ink = Color(0xFF171717)
val InkMuted = Color(0xFF6B7280)

private val LightColors = lightColorScheme(
  primary = Color(0xFF1A1A1A),
  onPrimary = Color(0xFFFAFAFA),
  primaryContainer = Color(0xFFDCE6FF),
  onPrimaryContainer = Color(0xFF001A45),
  secondary = AccentBlue,
  onSecondary = Color.White,
  secondaryContainer = Color(0xFFDCE6FF),
  onSecondaryContainer = Color(0xFF002B75),
  tertiary = Color(0xFF0F766E),
  background = SoftGrayBg,
  onBackground = Ink,
  surface = Color(0xFFFFFFFF),
  onSurface = Ink,
  surfaceVariant = Color(0xFFE9EBEF),
  onSurfaceVariant = InkMuted,
  surfaceContainerHigh = Color(0xFFECEEF2),
  outline = Color(0xFFD1D5DB),
  error = Color(0xFFB42318),
  onError = Color.White,
)

private val DarkColors = darkColorScheme(
  primary = Color(0xFFF3F4F6),
  onPrimary = Color(0xFF111111),
  primaryContainer = Color(0xFF2748A8),
  onPrimaryContainer = Color(0xFFDCE6FF),
  secondary = Color(0xFF8AB4F8),
  onSecondary = Color(0xFF062E6F),
  secondaryContainer = Color(0xFF2748A8),
  onSecondaryContainer = Color(0xFFDCE6FF),
  tertiary = Color(0xFF5EEAD4),
  background = Color(0xFF0F1115),
  onBackground = Color(0xFFF3F4F6),
  surface = Color(0xFF1A1D24),
  onSurface = Color(0xFFF3F4F6),
  surfaceVariant = Color(0xFF2A2F38),
  onSurfaceVariant = Color(0xFFB0B7C3),
  surfaceContainerHigh = Color(0xFF2A2F38),
  outline = Color(0xFF3F4654),
  error = Color(0xFFF2B8B5),
  onError = Color(0xFF601410),
)

private val AppTypography = Typography(
  headlineLarge = TextStyle(
    fontFamily = FontFamily.SansSerif,
    fontWeight = FontWeight.Bold,
    fontSize = 30.sp,
    lineHeight = 36.sp,
    letterSpacing = (-0.5).sp,
  ),
  headlineMedium = TextStyle(
    fontFamily = FontFamily.SansSerif,
    fontWeight = FontWeight.SemiBold,
    fontSize = 24.sp,
    lineHeight = 30.sp,
  ),
  titleLarge = TextStyle(
    fontWeight = FontWeight.SemiBold,
    fontSize = 20.sp,
    lineHeight = 26.sp,
  ),
  titleMedium = TextStyle(
    fontWeight = FontWeight.SemiBold,
    fontSize = 16.sp,
    lineHeight = 22.sp,
  ),
  bodyLarge = TextStyle(
    fontWeight = FontWeight.Normal,
    fontSize = 16.sp,
    lineHeight = 24.sp,
  ),
  bodyMedium = TextStyle(
    fontWeight = FontWeight.Normal,
    fontSize = 14.sp,
    lineHeight = 20.sp,
  ),
  bodySmall = TextStyle(
    fontWeight = FontWeight.Normal,
    fontSize = 12.sp,
    lineHeight = 16.sp,
    color = InkMuted,
  ),
  labelLarge = TextStyle(
    fontWeight = FontWeight.SemiBold,
    fontSize = 14.sp,
    lineHeight = 18.sp,
  ),
)

private val AppShapes = Shapes(
  extraSmall = RoundedCornerShape(8.dp),
  small = RoundedCornerShape(12.dp),
  medium = RoundedCornerShape(16.dp),
  large = RoundedCornerShape(22.dp),
  extraLarge = RoundedCornerShape(28.dp),
)

@Composable
fun EasyControlTheme(
  darkTheme: Boolean = isSystemInDarkTheme(),
  content: @Composable () -> Unit,
) {
  // System bars are applied once in Activity.onCreate via ComposeActivityBars.
  // Do not SideEffect-flip bar colors after first composition (causes flicker).
  MaterialTheme(
    colorScheme = if (darkTheme) DarkColors else LightColors,
    typography = AppTypography,
    shapes = AppShapes,
    content = content,
  )
}

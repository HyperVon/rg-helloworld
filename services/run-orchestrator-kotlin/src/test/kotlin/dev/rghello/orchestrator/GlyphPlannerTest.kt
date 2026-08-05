package dev.rghello.orchestrator

import dev.rghello.soap.generated.Glyph
import dev.rghello.soap.generated.Glyphs
import dev.rghello.soap.generated.PlanPhraseResponse
import dev.rghello.soap.generated.Point
import dev.rghello.soap.generated.Primitive
import dev.rghello.soap.generated.Primitives
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class GlyphPlannerTest {
    @Test
    fun toSoapPlanMapsResponseStructure() {
        val response = PlanPhraseResponse()
        response.planId = "plan-1"
        val glyphs = Glyphs()
        val h = Glyph()
        h.glyphInstanceId = "g-0"
        h.position = 0
        h.kind = "DRAWABLE"
        h.advanceWidth = 1.0
        val primitives = Primitives()
        val line = Primitive()
        line.type = "POLYLINE"
        val from = Point()
        from.x = 0.1
        from.y = 0.0
        val to = Point()
        to.x = 0.9
        to.y = 1.0
        line.points.add(from)
        line.points.add(to)
        primitives.primitive.add(line)
        h.primitives = primitives
        glyphs.glyph.add(h)
        response.glyphs = glyphs

        val plan = toSoapPlan(response)

        assertEquals("plan-1", plan.planId)
        assertEquals(1, plan.glyphs.size)
        val glyph = plan.glyphs[0]
        assertEquals("g-0", glyph.glyphInstanceId)
        assertEquals(0, glyph.position)
        assertEquals("DRAWABLE", glyph.kind)
        assertEquals(1.0, glyph.advanceWidth)
        assertEquals(1, glyph.primitives.size)
        assertEquals("POLYLINE", glyph.primitives[0].type)
        assertEquals(listOf(SoapPoint(0.1, 0.0), SoapPoint(0.9, 1.0)), glyph.primitives[0].points)
    }

    @Test
    fun toSoapPlanHandlesNullWrappers() {
        val response = PlanPhraseResponse()
        response.planId = "plan-empty"

        val plan = toSoapPlan(response)

        assertEquals("plan-empty", plan.planId)
        assertTrue(plan.glyphs.isEmpty())
    }

    @Test
    fun toSoapPlanMapsGapWithoutPrimitives() {
        val response = PlanPhraseResponse()
        response.planId = "plan-gap"
        val glyphs = Glyphs()
        val gap = Glyph()
        gap.glyphInstanceId = "g-gap"
        gap.position = 5
        gap.kind = "GAP"
        gap.advanceWidth = 0.6
        gap.primitives = Primitives()
        glyphs.glyph.add(gap)
        response.glyphs = glyphs

        val plan = toSoapPlan(response)

        assertEquals("GAP", plan.glyphs[0].kind)
        assertEquals(0.6, plan.glyphs[0].advanceWidth)
        assertTrue(plan.glyphs[0].primitives.isEmpty())
    }
}

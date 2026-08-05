package dev.rghello.orchestrator

import dev.rghello.soap.generated.GlyphCatalogService
import dev.rghello.soap.generated.PlanPhraseRequest
import dev.rghello.soap.generated.PlanPhraseResponse
import jakarta.xml.ws.BindingProvider

interface GlyphPlanner {
    fun plan(
        message: String,
        alphabet: String,
        variant: String,
    ): SoapPlan
}

data class SoapPoint(
    val x: Double,
    val y: Double,
)

data class SoapPrimitive(
    val type: String,
    val points: List<SoapPoint>,
)

data class SoapGlyph(
    val glyphInstanceId: String,
    val position: Int,
    val kind: String,
    val advanceWidth: Double,
    val primitives: List<SoapPrimitive>,
)

data class SoapPlan(
    val planId: String,
    val glyphs: List<SoapGlyph>,
)

class GlyphCatalogClient(
    private val endpointUrl: String,
) : GlyphPlanner {
    override fun plan(
        message: String,
        alphabet: String,
        variant: String,
    ): SoapPlan {
        val port = GlyphCatalogService().glyphCatalogPort
        (port as BindingProvider).requestContext[BindingProvider.ENDPOINT_ADDRESS_PROPERTY] = endpointUrl
        val request = PlanPhraseRequest()
        request.message = message
        request.alphabet = alphabet
        request.variant = variant
        return toSoapPlan(port.planPhrase(request))
    }
}

fun toSoapPlan(response: PlanPhraseResponse): SoapPlan {
    val glyphs = response.glyphs?.glyph ?: emptyList()
    return SoapPlan(
        planId = response.planId,
        glyphs =
            glyphs.map { glyph ->
                SoapGlyph(
                    glyphInstanceId = glyph.glyphInstanceId,
                    position = glyph.position,
                    kind = glyph.kind,
                    advanceWidth = glyph.advanceWidth,
                    primitives =
                        (glyph.primitives?.primitive ?: emptyList()).map { primitive ->
                            SoapPrimitive(
                                type = primitive.type,
                                points =
                                    primitive.points.map { point ->
                                        SoapPoint(x = point.x, y = point.y)
                                    },
                            )
                        },
                )
            },
    )
}

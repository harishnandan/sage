include '../../ext/stdsage.pxi'

from sage.structure.parent_gens cimport ParentWithGens
import sage.misc.latex
import multi_polynomial_ideal
from term_order import TermOrder
from sage.rings.integer_ring import ZZ
from sage.rings.polynomial.polydict import PolyDict
import multi_polynomial_element

def is_MPolynomialRing(x):
    return bool(PY_TYPE_CHECK(x, MPolynomialRing_generic))

cdef class MPolynomialRing_generic(sage.rings.ring.CommutativeRing):
    def __init__(self, base_ring, n, names, order):
        order = TermOrder(order,n)
        if not isinstance(base_ring, sage.rings.ring.CommutativeRing):
            raise TypeError, "Base ring must be a commutative ring."
        n = int(n)
        if n < 0:
            raise ValueError, "Multivariate Polynomial Rings must " + \
                  "have more than 0 variables."
        self.__ngens = n
        self.__term_order = order
        self._has_singular = False #cannot convert to Singular by default
        ParentWithGens.__init__(self, base_ring, names)

    def is_integral_domain(self):
        return self.base_ring().is_integral_domain()

    def construction(self):
        """
        Returns a functor F and basering R such that F(R) == self.

        In the multi-variate case, R is a polynomial ring with one
        less variable, and F knows to adjoin the variable in the
        correct way.

        EXAMPLES:
            sage: S = ZZ['x,y']
            sage: F, R = S.constructor(); R
            Univariate Polynomial Ring in x over Integer Ring
            sage: F(R) == S
            True
            sage: F(R) == ZZ['x']['y']
            False

        """
        from sage.rings.polynomial.polynomial_ring import PolynomialRing
        from sage.categories.pushout import PolynomialFunctor
        vars = self.variable_names()
        if len(vars) == 1:
            return PolynomialFunctor(vars[0], False), self.base_ring()
        else:
            return PolynomialFunctor(vars[-1], True), PolynomialRing(self.base_ring(), vars[:-1])

    cdef _coerce_c_impl(self, x):
        """
        Return the canonical coercion of x to this multivariate
        polynomial ring, if one is defined, or raise a TypeError.

        The rings that canonically coerce to this polynomial ring are:
            * this ring itself
            * polynomial rings in the same variables over any base ring that
              canonically coerces to the base ring of this ring
            * any ring that canonically coerces to the base ring of this
              polynomial ring.

        TESTS:
        This fairly complicated code (from Michel Vandenbergh) ends up
        imlicitly calling _coerce_c_impl:
            sage: z = polygen(QQ, 'z')
            sage: W.<s>=NumberField(z^2+1)
            sage: Q.<u,v,w> = W[]
            sage: W1 = FractionField (Q)
            sage: S.<x,y,z> = W1[]
            sage: u + x
            x + u
            sage: x + 1/u
            x + 1/u
        """
        try:
            P = x.parent()
            # polynomial rings in the same variable over the any base that coerces in:
            if is_MPolynomialRing(P):
                if P.variable_names() == self.variable_names():
                    if self.has_coerce_map_from(P.base_ring()):
                        return self(x)

        except AttributeError:
            pass

        # any ring that coerces to the base ring of this polynomial ring.
        return self._coerce_try(x, [self.base_ring()])

    def __richcmp__(left, right, int op):
        return (<ParentWithGens>left)._richcmp(right, op)

    cdef int _cmp_c_impl(left, Parent right) except -2:
        if not is_MPolynomialRing(right):
            return cmp(type(left),type(right))
        else:
            return cmp((left.base_ring(), left.__ngens, left.variable_names(), left.__term_order),
                       (right.base_ring(), (<MPolynomialRing_generic>right).__ngens, right.variable_names(), (<MPolynomialRing_generic>right).__term_order))

    def __contains__(self, x):
        """
        This definition of containment does not involve a natural
        inclusion from rings with less variables into rings with more.
        """
        try:
            return x.parent() == self
        except AttributeError:
            return False

    def _repr_(self):
        return "Polynomial Ring in %s over %s"%(", ".join(self.variable_names()), self.base_ring())

    def _latex_(self):
        vars = str(self.latex_variable_names()).replace('\n','').replace("'",'')
        return "%s[%s]"%(sage.misc.latex.latex(self.base_ring()), vars[1:-1])


    def _ideal_class_(self):
        return multi_polynomial_ideal.MPolynomialIdeal

    def _is_valid_homomorphism_(self, codomain, im_gens):
        try:
            # all that is needed is that elements of the base ring
            # of the polynomial ring canonically coerce into codomain.
            # Since poly rings are free, any image of the gen
            # determines a homomorphism
            codomain._coerce_(self.base_ring()(1))
        except TypeError:
            return False
        return True

    def _magma_(self, magma=None):
        """
        Used in converting this ring to the corresponding ring in MAGMA.

        EXAMPLES:
            sage: R.<y,z,w> = PolynomialRing(QQ,3)
            sage: magma(R) # optional
            Polynomial ring of rank 3 over Rational Field
            Graded Reverse Lexicographical Order
            Variables: y, z, w

            sage: magma(PolynomialRing(GF(7),4, 'x')) #optional
            Polynomial ring of rank 4 over GF(7)
            Graded Reverse Lexicographical Order
            Variables: x0, x1, x2, x3

            sage: magma(PolynomialRing(GF(49,'a'),10, 'x')) #optional
            Polynomial ring of rank 10 over GF(7^2)
            Graded Reverse Lexicographical Order
            Variables: x0, x1, x2, x3, x4, x5, x6, x7, x8, x9

            sage: magma(PolynomialRing(ZZ['a,b,c'],3, 'x')) #optional
            Polynomial ring of rank 3 over Polynomial ring of rank 3 over Integer Ring
            Graded Reverse Lexicographical Order
            Variables: x0, x1, x2
        """
        if magma == None:
            import sage.interfaces.magma
            magma = sage.interfaces.magma.magma

        try:
            if self.__magma is None:
                raise AttributeError
            m = self.__magma
            m._check_valid()
            if not m.parent() is magma:
                raise ValueError
            return m
        except (AttributeError,ValueError):
            B = magma(self.base_ring())
            R = magma('PolynomialRing(%s, %s, %s)'%(B.name(), self.ngens(),self.term_order().magma_str()))
            R.assign_names(self.variable_names())
            self.__magma = R
            return R

    def _magma_init_(self):
        B = self.base_ring()._magma_init_()
        R = 'PolynomialRing(%s, %s, %s)'%(B, self.ngens(),self.term_order().magma_str())
        return R

    def is_finite(self):
        if self.ngens() == 0:
            return self.base_ring().is_finite()
        return False

    def is_field(self):
        """
        Return True if this multivariate polynomial ring is a field, i.e.,
        it is a ring in 0 generators over a field.
        """
        if self.ngens() == 0:
            return self.base_ring().is_field()
        return False

    def term_order(self):
        return self.__term_order

    def characteristic(self):
        """
        Return the characteristic of this polynomial ring.

        EXAMPLES:
            sage: R = MPolynomialRing(QQ, 'x', 3)
            sage: R.characteristic()
            0
            sage: R = MPolynomialRing(GF(7),'x', 20)
            sage: R.characteristic()
            7
        """
        return self.base_ring().characteristic()

    def gen(self, n=0):
        if n < 0 or n >= self.__ngens:
            raise ValueError, "Generator not defined."
        return self._gens[int(n)]

    def gens(self):
        return self._gens

    def krull_dimension(self):
        return self.base_ring().krull_dimension() + self.ngens()

    def ngens(self):
        return self.__ngens

    def _monomial_order_function(self):
        raise NotImplementedError

    def latex_variable_names(self):
        """
        Returns the list of variable names suitable for latex output.

        All '_SOMETHING' substrings are replaced by '_{SOMETHING}' recursively
        so that subscripts of subscripts work.

        EXAMPLES:
            sage: R, x = PolynomialRing(QQ,'x',12).objgens()
            sage: x
            (x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11)
            sage: print R.latex_variable_names ()
            ['x_{0}', 'x_{1}', 'x_{2}', 'x_{3}', 'x_{4}', 'x_{5}', 'x_{6}', 'x_{7}', 'x_{8}', 'x_{9}', 'x_{10}', 'x_{11}']
            sage: f = x[0]^3 + 15/3 * x[1]^10
            sage: print latex(f)
            5 x_{1}^{10} + x_{0}^{3}
        """
        if self._latex_names is not None:
            return self._latex_names
        names = []
        for g in self.variable_names():
            i = len(g)-1
            while i >= 0 and g[i].isdigit():
                i -= 1
            if i < len(g)-1:
                g = '%s_{%s}'%(g[:i+1], g[i+1:])
            names.append(g)
        self._latex_names = names
        return names

    def __reduce__(self):
        """
        """

        base_ring = self.base_ring()
        n = self.ngens()
        names = self.variable_names()
        order = self.term_order()

        return unpickle_MPolynomialRing_generic_v1,(base_ring, n, names, order)


    def random_element(self, degree=2, terms=5, *args, **kwds):
        r"""
        Return a random polynomial in this polynomial ring.

        INPUT:
            degree -- maximum total degree of resulting polynomial
            terms  -- maximum number of terms to generate

        OUTPUT: a random polynomial of total degree \code{degree}
                and with \code{term} terms in it.

        EXAMPLES:
            sage: [QQ['x,y'].random_element() for _ in range(5)]
            [-1/14*x*y + 1/2*x, x*y + x - y + 1, 3*x*y + x - 1/2, 1/3*x*y - 5*x + 1/2*y + 7/6, 2*x*y + 1/2*x + 1]
            sage: R = MPolynomialRing(ZZ, 'x,y',2 );
            sage: R.random_element(2)          # random
            -1*x*y + x + 15*y - 2
            sage: R.random_element(12)         # random
            x^4*y^5 + x^3*y^5 + 6*x^2*y^2 - x^2
            sage: R.random_element(12,3)       # random
            -3*x^4*y^2 - x^5 - x^4*y
            sage: R.random_element(3)          # random
            2*y*z + 2*x + 2*y

            sage: R.<x,y> = MPolynomialRing(RR)
            sage: R.random_element(2)          # random
            -0.645358174399450*x*y + 0.572655401740132*x + 0.197478565033010

            sage: R.random_element(41)         # random
            -4*x^6*y^4*z^4*a^6*b^3*c^6*d^5 + 1/2*x^4*y^3*z^5*a^4*c^5*d^6 - 5*x^3*z^3*a^6*b^4*c*d^5 + 10*x^2*y*z^5*a^4*b^2*c^3*d^4 - 5*x^3*y^5*z*b^2*c^5*d

        AUTHOR:
            -- didier deshommes
        """
        # General strategy:
        # generate n-tuples of numbers with each element in the tuple
        # not greater than  (degree/n) so that the degree
        # (ie, the sum of the elements in the tuple) does not exceed
        # their total degree

        n = self.__ngens         # length of the n-tuple
        max_deg = int(degree/n)  # max degree for each term
        R = self.base_ring()

        # restrict exponents to positive integers only
        exponents = [ tuple([ZZ.random_element(0,max_deg+1) for _ in range(n)])
                       for _ in range(terms) ]
        coeffs = []
        for _ in range(terms):
            c = R.random_element(*args,**kwds)
            while not c:
                c = R.random_element(*args,**kwds)
            coeffs.append(c) # allow only nonzero coefficients

        d = dict( zip(tuple(exponents), coeffs) )
        return self(multi_polynomial_element.MPolynomial_polydict(self, PolyDict(d)))


####################
# Leave *all* old versions!

def unpickle_MPolynomialRing_generic_v1(base_ring, n, names, order):
    from sage.rings.polynomial.multi_polynomial_ring import MPolynomialRing
    return MPolynomialRing(base_ring, n, names=names, order=order)


def unpickle_MPolynomialRing_generic(base_ring, n, names, order):
    from sage.rings.polynomial.multi_polynomial_ring import MPolynomialRing

    return MPolynomialRing(base_ring, n, names=names, order=order)

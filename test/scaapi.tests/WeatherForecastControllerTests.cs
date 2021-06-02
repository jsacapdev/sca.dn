using System;
using System.Linq;
using scaapi.Controllers;
using Xunit;

namespace scaapi.tests
{
    public class WeatherForecastControllerTests
    {
        [Fact]
        public void WeatherForecastController_Get_Returns_Ok()
        {
            var controller = new WeatherForecastController()
            {
            };

            var results = controller.Get();

            Assert.NotNull(results);

            Assert.Equal(5, results.Count());
        }
    }
}
